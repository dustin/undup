//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");
const testing = std.testing;

pub const Options = struct {
    verbose: bool = false,
    remove: bool = false,
    help: bool = false,

    pub const shorthands = .{
        .h = "help",
        .v = "verbose",
        .r = "remove",
    };

    pub const meta = .{
        .option_docs = .{
            .verbose = "verbose mode",
            .help = "help help",
            .remove = "remove duplicates",
        },
    };

    pub fn debug(o: @This(), comptime format: []const u8, args: anytype) void {
        if (o.verbose) {
            std.debug.print(format, args);
        }
    }
};

const hash = std.crypto.hash.Sha1;

const Duplicate = struct {
    path: []const u8,
    size: usize,
    hash: ?[hash.digest_length]u8 = null,

    fn deinit(self: *Duplicate, alloc: std.mem.Allocator) void {
        alloc.free(self.path);
    }
};

fn hashFile(dir: *std.fs.Dir, f: *Duplicate) !void {
    if (f.hash != null) {
        return;
    }
    const file = try dir.openFile(f.path, .{});
    defer file.close();

    var hasher = hash.init(.{});
    var buffer: [4096]u8 = undefined;
    while (true) {
        const bytes_read = try file.read(buffer[0..]);

        if (bytes_read == 0) break;
        hasher.update(buffer[0..bytes_read]);
    }
    f.hash = @as([hash.digest_length]u8, undefined);
    hasher.final(&f.hash.?);
}

fn contentEq(dir: *std.fs.Dir, a: *Duplicate, b: *Duplicate) !bool {
    if (a.size != b.size) {
        return false;
    }
    try hashFile(dir, a);
    try hashFile(dir, b);
    return std.meta.eql(a.hash, b.hash);
}

pub fn findFiles(alloc: std.mem.Allocator, opts: Options, dir: *std.fs.Dir, res: *std.ArrayList([]const u8)) !void {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const aalloc = arena.allocator();
    var seen = std.StringHashMap(Duplicate).init(aalloc);

    var walker = try dir.walk(alloc);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .file) {
            continue;
        }
        const kc = try aalloc.dupe(u8, entry.basename);
        const stat = try dir.statFile(entry.path);
        var tmpd = Duplicate{ .path = entry.path, .size = stat.size };
        const me = try seen.getOrPut(kc);
        if (me.found_existing) {
            defer aalloc.free(kc);
            opts.debug("found duplicate filename:\n  {s}\n  {s}\n", .{ entry.path, me.value_ptr.*.path });
            // If these files don't contain the same content, then we will not deduplicate them.
            if (!try contentEq(dir, me.value_ptr, &tmpd)) {
                opts.debug("  (content mismatch -- ignoring)\n", .{});
                continue;
            }
            // We have a valid duplicate.  We will keep whichever has a path that sorts lower.
            // For the intended use cases, files contain ISO8601 dates, so lower is older.
            if (std.mem.order(u8, entry.path, me.value_ptr.*.path) == .lt) {
                try res.append(alloc, try alloc.dupe(u8, me.value_ptr.*.path));
                me.value_ptr.*.deinit(aalloc);
                tmpd.path = try aalloc.dupe(u8, tmpd.path);
                me.value_ptr.* = tmpd;
            } else {
                try res.append(alloc, try alloc.dupe(u8, entry.path));
            }
        } else {
            tmpd.path = try aalloc.dupe(u8, tmpd.path);
            me.value_ptr.* = tmpd;
        }
    }
}

pub fn freeAll(allocator: std.mem.Allocator, l: *std.ArrayList([]const u8)) void {
    for (l.items) |i| {
        allocator.free(i);
    }
    l.clearAndFree(allocator);
}

test "findFiles" {
    // Create a temporary directory for testing
    var temp_dir = std.testing.tmpDir(.{ .iterate = true, .access_sub_paths = true });
    defer temp_dir.cleanup();

    const TestData = struct {
        path: []const u8,
        data: []const u8,
    };

    const testData = [_]TestData{
        .{ .path = "a", .data = "" },
        .{ .path = "b", .data = "" },
        .{ .path = "d/a", .data = "" },
        .{ .path = "d/b", .data = "stuff" },
    };

    try temp_dir.dir.makeDir("d");
    for (testData) |t| {
        const file = try temp_dir.dir.createFile(t.path, .{});
        defer file.close();
        _ = try file.write(t.data);
    }

    var found = try std.ArrayList([]const u8).initCapacity(std.testing.allocator, 4);
    defer freeAll(std.testing.allocator, &found);
    try findFiles(std.testing.allocator, .{}, &temp_dir.dir, &found);

    try testing.expectEqual(found.items.len, 1);
    try testing.expectEqualStrings(found.items[0], "d/a");
}

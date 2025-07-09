//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");
const testing = std.testing;

const Duplicate = struct {
    path: []const u8,
    size: usize,
    hash: ?[std.crypto.hash.Sha1.digest_length]u8 = null,

    fn deinit(self: *Duplicate, alloc: std.mem.Allocator) void {
        alloc.free(self.path);
    }
};

fn hashFile(alloc: std.mem.Allocator, root: []const u8, f: *Duplicate) !void {
    if (f.hash != null) {
        return;
    }
    const fullPath = try std.fs.path.join(alloc, &.{ root, f.path });
    defer alloc.free(fullPath);
    const file = try std.fs.cwd().openFile(fullPath, .{});
    defer file.close();

    var hasher = std.crypto.hash.Sha1.init(.{});
    var buffer: [4096]u8 = undefined;
    while (true) {
        const bytes_read = try file.read(buffer[0..]);

        if (bytes_read == 0) break;
        hasher.update(buffer[0..bytes_read]);
    }
    f.hash = @as([std.crypto.hash.Sha1.digest_length]u8, undefined);
    hasher.final(&f.hash.?);
}

fn contentEq(alloc: std.mem.Allocator, root: []const u8, a: *Duplicate, b: *Duplicate) !bool {
    if (a.size != b.size) {
        return false;
    }
    try hashFile(alloc, root, a);
    try hashFile(alloc, root, b);
    return std.meta.eql(a.hash, b.hash);
}

pub fn findFiles(alloc: std.mem.Allocator, root: []const u8, res: *std.ArrayList([]const u8)) !void {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const aalloc = arena.allocator();
    var seen = std.StringHashMap(Duplicate).init(aalloc);

    var dir = try std.fs.openDirAbsolute(root, .{ .iterate = true, .access_sub_paths = true });
    defer dir.close();
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
            // std.debug.print("found duplicate filename:\n  {s}\n  {s}\n", .{ entry.path, me.value_ptr.*.path });            // Ignore files if the hashes don't match
            // If these files don't contain the same content, then we will not deduplicate them.
            if (!try contentEq(alloc, root, me.value_ptr, &tmpd)) {
                continue;
            }
            // We have a valid duplicate.  We will keep whichever has a path that sorts lower.
            // For the intended use cases, files contain ISO8601 dates, so lower is older.
            if (std.mem.order(u8, entry.path, me.value_ptr.*.path) == .lt) {
                try res.append(me.value_ptr.*.path);
                me.value_ptr.*.deinit(aalloc);
                tmpd.path = try aalloc.dupe(u8, tmpd.path);
                me.value_ptr.* = tmpd;
            } else {
                try res.append(try alloc.dupe(u8, entry.path));
            }
        } else {
            tmpd.path = try aalloc.dupe(u8, tmpd.path);
            me.value_ptr.* = tmpd;
        }
    }
}

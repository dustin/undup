//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");
const testing = std.testing;

const Duplicate = struct {
    path: []const u8,
    hash: [std.crypto.hash.Sha1.digest_length]u8 = undefined,
    hashed: bool = false,
};

fn hashFile(alloc: std.mem.Allocator, root: []const u8, f: *Duplicate) !void {
    if (f.hashed) {
        return;
    }
    const fullPath = try std.fs.path.join(alloc, &.{ root, f.path });
    defer alloc.free(fullPath);
    f.hashed = true;
    const file = try std.fs.cwd().openFile(fullPath, .{});
    defer file.close();

    var hasher = std.crypto.hash.Sha1.init(.{});
    var buffer: [4096]u8 = undefined;
    while (true) {
        const bytes_read = try file.readAll(&buffer);

        if (bytes_read == 0) break;
        hasher.update(buffer[0..bytes_read]);
    }
    hasher.final(&f.hash);
}

fn deinitMap(alloc: std.mem.Allocator, m: *std.StringHashMap(Duplicate)) void {
    defer m.deinit();
    var iterator = m.iterator();
    while (iterator.next()) |entry| {
        alloc.free(entry.key_ptr.*);
        alloc.free(entry.value_ptr.*.path);
    }
}

pub fn findFiles(alloc: std.mem.Allocator, root: []const u8, res: *std.ArrayList([]const u8)) !void {
    var seen = std.StringHashMap(Duplicate).init(alloc);
    defer deinitMap(alloc, &seen);

    var dir = try std.fs.openDirAbsolute(root, .{ .iterate = true, .access_sub_paths = true });
    defer dir.close();
    var walker = try dir.walk(alloc);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .file) {
            std.debug.print("// ignoring {s} ({any})\n", .{ entry.path, entry.kind });
            continue;
        }
        const kc = try alloc.dupe(u8, entry.basename);
        var tmpd = Duplicate{ .path = try alloc.dupe(u8, entry.path) };
        const me = try seen.getOrPut(kc);
        if (me.found_existing) {
            defer alloc.free(kc);
            std.debug.print("found duplicate filename:\n  {s}\n  {s}\n", .{ entry.path, me.value_ptr.*.path });
            try hashFile(alloc, root, me.value_ptr);

            try hashFile(alloc, root, &tmpd);
            // Ignore files if the hashes don't match
            if (!std.meta.eql(me.value_ptr.*.hash, tmpd.hash)) {
                std.debug.print(" - hashes differ ({x} vs {x})\n", .{ me.value_ptr.*.hash, tmpd.hash });
                alloc.free(tmpd.path);
                continue;
            }
            // We want to keep the file with the smaller name
            if (std.mem.order(u8, entry.path, me.value_ptr.*.path) == .lt) {
                std.debug.print(" - new file has lesser name: {s}\n", .{entry.path});
                try res.append(me.value_ptr.*.path);
                me.value_ptr.* = tmpd;
            } else {
                alloc.free(tmpd.path);
                std.debug.print(" - old file has lesser name: {s}\n", .{me.value_ptr.*.path});
                try res.append(try alloc.dupe(u8, entry.path));
            }
        } else {
            me.value_ptr.* = tmpd;
        }
    }
}

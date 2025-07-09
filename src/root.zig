//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");
const testing = std.testing;

const Duplicate = struct {
    path: []const u8,
    size: usize,
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
        const bytes_read = try file.read(buffer[0..]);

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
            continue;
        }
        const kc = try alloc.dupe(u8, entry.basename);
        const stat = try dir.statFile(entry.path);
        var tmpd = Duplicate{ .path = try alloc.dupe(u8, entry.path), .size = stat.size };
        const me = try seen.getOrPut(kc);
        if (me.found_existing) {
            defer alloc.free(kc);
            if (me.value_ptr.*.size != tmpd.size) {
                alloc.free(tmpd.path);
                continue;
            }
            // std.debug.print("found duplicate filename:\n  {s}\n  {s}\n", .{ entry.path, me.value_ptr.*.path });
            try hashFile(alloc, root, me.value_ptr);
            try hashFile(alloc, root, &tmpd);
            // Ignore files if the hashes don't match
            if (!std.meta.eql(me.value_ptr.*.hash, tmpd.hash)) {
                alloc.free(tmpd.path);
                continue;
            }
            // We want to keep the file with the smaller name
            if (std.mem.order(u8, entry.path, me.value_ptr.*.path) == .lt) {
                try res.append(me.value_ptr.*.path);
                me.value_ptr.* = tmpd;
            } else {
                alloc.free(tmpd.path);
                try res.append(try alloc.dupe(u8, entry.path));
            }
        } else {
            me.value_ptr.* = tmpd;
        }
    }
}

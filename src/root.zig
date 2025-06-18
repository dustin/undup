//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");
const testing = std.testing;

const Duplicate = struct {
    path: []const u8,
    hash: ?[std.crypto.hash.Sha1.digest_length]u8 = null,
};

fn hashFile(f: *Duplicate) !void {
    if (f.hash != null) {
        return;
    }
    const file = try std.fs.cwd().openFile(f.path, .{});
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
    std.debug.print("Remaining:\n", .{});
    while (iterator.next()) |entry| {
        // std.debug.print("  {s} {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
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

    // pub fn next(self: *Walker) !?Walker.Entry
    while (try walker.next()) |entry| {
        const kc = try alloc.dupe(u8, entry.basename);
        const me = try seen.getOrPut(kc);
        // std.debug.print("Working on {s}\n", .{entry.basename});
        if (me.found_existing) {
            defer alloc.free(kc);
            std.debug.print("found duplicate filename:\n  {s}\n  {s}\n", .{ entry.path, me.value_ptr.*.path });
            if (std.mem.order(u8, entry.path, me.value_ptr.*.path) == .lt) {
                std.debug.print(" - new file has lesser name: {s}\n", .{entry.path});
                try res.append(me.value_ptr.*.path);
                // alloc.free(me.value_ptr.*);
                me.value_ptr.* = .{ .path = try alloc.dupe(u8, entry.path) };
            } else {
                std.debug.print(" - old file has lesser name: {s}\n", .{me.value_ptr.*.path});
                try res.append(try alloc.dupe(u8, entry.path));
            }
        } else {
            me.value_ptr.* = .{ .path = try alloc.dupe(u8, entry.path) };
        }
    }
}

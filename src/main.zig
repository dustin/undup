const lib = @import("undup_lib");
const std = @import("std");

fn wait() !void {
    const stdin = std.io.getStdIn().reader();
    var lineBuf: [256]u8 = undefined;
    _ = try stdin.readUntilDelimiterOrEof(&lineBuf, '\n');
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        _ = gpa.deinit();
    }
    const allocator = gpa.allocator();

    const args = std.process.argsAlloc(allocator) catch return;
    defer std.process.argsFree(allocator, args);

    var torm = std.ArrayList([]const u8).init(allocator);
    defer lib.freeAll(allocator, &torm);
    var dir = try std.fs.openDirAbsolute(args[1], .{ .iterate = true, .access_sub_paths = true });
    defer dir.close();
    lib.findFiles(allocator, &dir, &torm) catch |err| {
        std.debug.print("Error finding files: {s}\n", .{@errorName(err)});
        return;
    };
    const stdout = std.io.getStdOut().writer();
    for (torm.items) |i| {
        try stdout.print("{s}\n", .{i});
    }
    std.debug.print("Shall we delete? (press enter, otherwise ^C)\n", .{});
    try wait();
    try lib.deleteFiles(&dir, torm.items);
    std.debug.print("Deleted {d} files\n", .{torm.items.len});
}

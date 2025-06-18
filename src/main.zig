const lib = @import("undup_lib");
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        _ = gpa.deinit();
    }
    const allocator = gpa.allocator();

    const args = std.process.argsAlloc(allocator) catch return;
    defer std.process.argsFree(allocator, args);

    var torm = std.ArrayList([]const u8).init(allocator);
    defer torm.clearAndFree();
    try lib.findFiles(allocator, args[1], &torm);

    const stdout = std.io.getStdOut().writer();
    for (torm.items) |i| {
        try stdout.print("{s}\n", .{i});
        allocator.free(i);
    }
}

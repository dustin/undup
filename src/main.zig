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
    var shouldPrint = true;
    lib.findFiles(allocator, args[1], &torm) catch |err| {
        std.debug.print("Error finding files: {s}\n", .{@errorName(err)});
        shouldPrint = false;
    };

    const stdout = std.io.getStdOut().writer();
    for (torm.items) |i| {
        if (shouldPrint) {
            try stdout.print("{s}\n", .{i});
        }
        allocator.free(i);
    }
}

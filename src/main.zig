const lib = @import("undup_lib");
const std = @import("std");

fn freeAll(allocator: std.mem.Allocator, l: *std.ArrayList([]const u8)) void {
    for (l.items) |i| {
        allocator.free(i);
    }
    l.clearAndFree();
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
    defer freeAll(allocator, &torm);
    lib.findFiles(allocator, args[1], &torm) catch |err| {
        std.debug.print("Error finding files: {s}\n", .{@errorName(err)});
        return;
    };

    const stdout = std.io.getStdOut().writer();
    for (torm.items) |i| {
        try stdout.print("{s}\n", .{i});
    }
}

const lib = @import("undup");
const std = @import("std");
const argsParser = @import("args");

fn wait() !void {
    const stdin = std.io.getStdIn().reader();
    var lineBuf: [256]u8 = undefined;
    _ = try stdin.readUntilDelimiterOrEof(&lineBuf, '\n');
}

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        _ = gpa.deinit();
    }
    const allocator = gpa.allocator();

    const options = argsParser.parseForCurrentProcess(lib.Options, allocator, .print) catch return 1;
    defer options.deinit();

    var writer_buf: [128]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&writer_buf);
    defer stdout.interface.flush() catch unreachable;

    if (options.options.help or options.positionals.len == 0) {
        try argsParser.printHelp(lib.Options, options.executable_name orelse "demo", &stdout.interface);
        return 1;
    }

    for (options.positionals) |arg| {
        var torm = try std.ArrayList([]const u8).initCapacity(allocator, 10);
        defer lib.freeAll(allocator, &torm);
        var dir = try std.fs.openDirAbsolute(arg, .{ .iterate = true, .access_sub_paths = true });
        defer dir.close();
        lib.findFiles(allocator, options.options, &dir, &torm) catch |err| {
            std.debug.print("Error finding files: {s}\n", .{@errorName(err)});
            return 1;
        };
        for (torm.items) |i| {
            try stdout.interface.print("{s}\n", .{i});
            if (options.options.remove) {
                options.options.debug("Deleting {s}\n", .{i});
                try dir.deleteFile(i);
            }
        }

        if (options.options.remove) {
            options.options.debug("Deleted {d} files\n", .{torm.items.len});
        }
    }

    return 0;
}

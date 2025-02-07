const std = @import("std");

// ANSI Escape Codes
// https://gist.github.com/fnky/458719343aabd01cfb17a3a4f7296797

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer {
        _ = gpa.deinit();
    }

    const screen = try Screen.init(alloc);
    // std.debug.print("Screen: {any}\n", .{screen});

    // try normalScreen(screen);
    try privateANSIMode(screen);
}

fn privateANSIMode(screen: Screen) !void {
    // Save screen
    // std.debug.print("\x1b[?47h", .{});

    // Enables the alternative buffer
    std.debug.print("\x1b[?1049h", .{});
    // Go to 0:0
    std.debug.print("\x1b[0;0H", .{});

    // Go to 0:0 & Clear screen (not necessary when using alternative buffer)
    // std.debug.print("\x1b[0;0H", .{});
    // std.debug.print("\x1b[J", .{});
    // std.debug.print("\x1b[0;0H", .{});

    for (0..screen.height) |y| {
        if (y != 0) {
            std.debug.print("\n", .{});
        }
        for (0..screen.width) |x| {
            _ = x;
            std.debug.print("a", .{});
            std.time.sleep(250 * std.time.ns_per_us);
        }
    }

    // std.debug.print("\x1b[0;0H", .{});
    // Clear screen
    // std.debug.print("\x1b[J", .{});

    // Disable the alternative buffer
    std.debug.print("\x1b[?1049l", .{});

    // Restore screen
    // std.debug.print("\x1b[?47l", .{});
}

fn normalScreen(screen: Screen) !void {
    for (0..screen.height - 1) |_| {
        std.debug.print("\n", .{});
    }

    std.debug.print("\x1b[{d}A", .{screen.height});
    std.debug.print("\x1b[0;0H", .{});

    for (0..screen.height) |y| {
        if (y != 0) {
            std.debug.print("\n", .{});
        }
        for (0..screen.width) |x| {
            _ = x;
            std.debug.print("a", .{});
            std.time.sleep(250 * std.time.ns_per_us);
        }
    }

    std.debug.print("\x1b[0;0H", .{});
    std.debug.print("\x1b[J", .{});
}

const Screen = struct {
    width: usize,
    height: usize,

    fn init(alloc: std.mem.Allocator) !Screen {
        const resultWidth = try std.process.Child.run(.{ .allocator = alloc, .argv = &.{ "tput", "cols" } });
        defer {
            alloc.free(resultWidth.stderr);
            alloc.free(resultWidth.stdout);
        }
        const width = resultWidth.stdout;

        const resultHeight = try std.process.Child.run(.{ .allocator = alloc, .argv = &.{ "tput", "lines" } });
        defer {
            alloc.free(resultHeight.stderr);
            alloc.free(resultHeight.stdout);
        }
        const height = resultHeight.stdout;

        return .{
            .width = std.fmt.parseInt(usize, width[0 .. width.len - 1], 10) catch return error.UnableToParseWidth,
            .height = std.fmt.parseInt(usize, height[0 .. height.len - 1], 10) catch return error.UnableToParseHeight,
        };
    }
};

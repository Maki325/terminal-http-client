const std = @import("std");

// ANSI Escape Codes
// https://gist.github.com/fnky/458719343aabd01cfb17a3a4f7296797

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer {
        _ = gpa.deinit();
    }

    var screen = try Screen.init(alloc);
    defer screen.deinit();

    const text = try alloc.dupe(u8, "0123456789");
    defer alloc.free(text);
    screen.render(try Text.init(text, 10));

    try privateANSIMode(screen);
}

fn privateANSIMode(screen: Screen) !void {
    // Enables the alternative buffer
    std.debug.print("\x1b[?1049h", .{});
    // Go to 0:0
    std.debug.print("\x1b[0;0H", .{});

    for (0..screen.height) |y| {
        if (y != 0) {
            std.debug.print("\n", .{});
        }
        for (0..screen.width) |x| {
            const char = &screen.buffer[y * screen.width + x];
            if (char.data[0] == 0) {
                std.debug.print(" ", .{});
            } else {
                for (char.data) |c| {
                    if (c == 0) break;
                    std.debug.print("{c}", .{c});
                }
            }
        }
    }

    std.time.sleep(1 * std.time.ns_per_s);

    // Disable the alternative buffer
    std.debug.print("\x1b[?1049l", .{});
}

const Char = struct {
    // This is so there's enough bytes to do ANSI Escape Codes before the actual char
    // We'll mostly be skipping 11/12 chars, if not 12/12
    // Since it's all in linear memory skipping should not slow it down (that much)
    data: [12]u8,

    fn fromChar(c: u8) Char {
        var char = std.mem.zeroes(Char);
        char.data[0] = c;
        return char;
    }
};

const Screen = struct {
    width: usize,
    height: usize,

    alloc: std.mem.Allocator,
    buffer: []Char,

    fn init(alloc: std.mem.Allocator) !Screen {
        const resultWidth = try std.process.Child.run(.{ .allocator = alloc, .argv = &.{ "tput", "cols" } });
        defer {
            alloc.free(resultWidth.stderr);
            alloc.free(resultWidth.stdout);
        }
        const widthStr = resultWidth.stdout;
        const width = std.fmt.parseInt(usize, widthStr[0 .. widthStr.len - 1], 10) catch return error.UnableToParseWidth;

        const resultHeight = try std.process.Child.run(.{ .allocator = alloc, .argv = &.{ "tput", "lines" } });
        defer {
            alloc.free(resultHeight.stderr);
            alloc.free(resultHeight.stdout);
        }
        const heightStr = resultHeight.stdout;
        const height = std.fmt.parseInt(usize, heightStr[0 .. heightStr.len - 1], 10) catch return error.UnableToParseHeight;

        const buffer = try alloc.alloc(Char, width * height);
        @memset(buffer, std.mem.zeroes(Char));

        return .{
            .width = width,
            .height = height,
            .alloc = alloc,
            .buffer = buffer,
        };
    }

    fn deinit(self: *Screen) void {
        self.alloc.free(self.buffer);
    }

    fn render(self: *Screen, component: anytype) void {
        component.render(self, 0, 0);
    }
};

const Text = struct {
    value: []u8,
    max_chars: usize,

    fn init(text: []u8, max_chars: usize) !Text {
        return .{
            .value = text,
            .max_chars = max_chars,
        };
    }

    fn render(self: *const Text, screen: *Screen, x: usize, y: usize) void {
        for (0..self.max_chars + 2) |i| {
            screen.buffer[y * screen.width + x + i] = Char.fromChar('-');
        }

        screen.buffer[(y + 1) * screen.width + x] = Char.fromChar('|');
        for (self.value, 0..) |c, i| {
            if (i >= self.max_chars) {
                break;
            }

            if (i == 0) {
                var char = std.mem.zeroes(Char);
                char.data[0] = '\x1b';
                char.data[1] = '[';
                char.data[2] = '1';
                char.data[3] = ';';
                char.data[4] = '3';
                char.data[5] = '1';
                char.data[6] = 'm';
                char.data[7] = c;

                if (self.value.len == 1) {
                    char.data[8] = '\x1b';
                    char.data[9] = '[';
                    char.data[10] = '0';
                    char.data[11] = 'm';
                }

                screen.buffer[(y + 1) * screen.width + x + 1 + i] = char;
            } else if (i == self.value.len - 1 or i == self.max_chars - 1) {
                var char = std.mem.zeroes(Char);
                char.data[0] = c;
                char.data[1] = '\x1b';
                char.data[2] = '[';
                char.data[3] = '0';
                char.data[4] = 'm';

                screen.buffer[(y + 1) * screen.width + x + 1 + i] = char;
            } else {
                screen.buffer[(y + 1) * screen.width + x + 1 + i] = Char.fromChar(c);
            }
        }

        screen.buffer[(y + 1) * screen.width + x + 1 + self.max_chars] = Char.fromChar('|');

        for (0..self.max_chars + 2) |i| {
            screen.buffer[(y + 2) * screen.width + x + i] = Char.fromChar('-');
        }
    }
};

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

    var text_component = Text.init(text, 10);

    const padding_options: Padding.Options = .{ .sided = .{
        .left = 1,
        .top = 2,
        .right = 3,
        .bottom = 4,
    } };

    var text_with_padding = Padding.init(text_component.to_component(), padding_options);

    // const border_options =.{ .char = '.' };
    const border_options: Border.Options = .{ .sided = .{
        .top = '-',
        .left = '|',
        .bottom = '-',
        .right = '|',
    } };
    var text_with_border = Border.init(text_with_padding.to_component(), border_options);

    var container = Container.init(
        text_with_border.to_component(),
        .{
            .width = screen.width - 2,
            .height = screen.height - 2,
            .alignment = .Middle,
        },
    );

    var container_with_border = Border.init(container.to_component(), border_options);

    // screen.render(container_with_border.to_component());
    // try privateANSIMode(screen);

    for (0..@typeInfo(Container.Alignment).Enum.fields.len) |i| {
        // if (true) {
        //     break;
        // }
        const alignment: Container.Alignment = @enumFromInt(i);

        container.options.alignment = alignment;
        screen.clear();
        screen.render(container_with_border.to_component());
        try privateANSIMode(screen);
    }
}

fn privateANSIMode(screen: Screen) !void {
    // Enables the alternative buffer
    std.debug.print("\x1b[?1049h", .{});
    // Go to 0:0
    std.debug.print("\x1b[0;0H", .{});
    // Make cursor invisible
    std.debug.print("\x1b[?25l", .{});

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

    std.time.sleep(750 * std.time.ns_per_ms);

    // Make cursor visible
    std.debug.print("\x1b[?25h", .{});

    // Disable the alternative buffer
    std.debug.print("\x1b[?1049l", .{});
}

const Component = struct {
    ctx: *anyopaque,
    vtable: VTable,

    const VTable = struct {
        constraints: *const fn (self: *const anyopaque) Constraints,
        render: *const fn (self: *const anyopaque, screen: *Screen, x: usize, y: usize) void,
    };

    fn constraints(self: *const Component) Constraints {
        return self.vtable.constraints(self.ctx);
    }

    fn render(self: *const Component, screen: *Screen, x: usize, y: usize) void {
        self.vtable.render(self.ctx, screen, x, y);
    }
};

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

    fn empty() Char {
        return std.mem.zeroes(Char);
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

    fn clear(self: *Screen) void {
        @memset(self.buffer, std.mem.zeroes(Char));
    }

    fn setChar(self: *Screen, x: usize, y: usize, char: Char) void {
        if (x > self.width or x < 0) return;
        if (y > self.height or y < 0) return;

        self.buffer[y * self.width + x] = char;
    }

    fn render(self: *Screen, component: Component) void {
        component.render(self, 0, 0);
    }
};

const Container = struct {
    const vtable = Component.VTable{
        .constraints = constraints,
        .render = render,
    };

    component: Component,
    options: Options,

    fn init(component: Component, options: Options) Container {
        return .{
            .component = component,
            .options = options,
        };
    }

    fn constraints(ctx: *const anyopaque) Constraints {
        const self: *const Container = @ptrCast(@alignCast(ctx));
        return Constraints{
            .width = self.options.width,
            .height = self.options.height,
        };
    }

    fn render(ctx: *const anyopaque, screen: *Screen, x: usize, y: usize) void {
        const self: *const Container = @ptrCast(@alignCast(ctx));
        const component_constraints: Constraints = self.component.constraints();

        // We should probably fill in the "empty" space with null chars
        // Since the space might NOT be empty
        // And we do that with the `Padding` component

        const alignment = self.options.alignment orelse Alignment.TopLeft;
        switch (alignment) {
            .TopLeft => {
                self.component.render(screen, x, y);
            },
            .TopMiddle => {
                const x_offset = @divTrunc(@max(self.options.width - component_constraints.width, 0), 2);

                self.component.render(screen, x + x_offset, y);
            },
            .TopRight => {
                const x_offset = @max(self.options.width - component_constraints.width, 0);
                self.component.render(screen, x + x_offset, y);
            },

            .MiddleLeft => {
                const y_offset = @divTrunc(@max(self.options.height - component_constraints.height, 0), 2);

                self.component.render(screen, x, y + y_offset);
            },
            .Middle => {
                const x_offset = @divTrunc(@max(self.options.width - component_constraints.width, 0), 2);
                const y_offset = @divTrunc(@max(self.options.height - component_constraints.height, 0), 2);

                self.component.render(screen, x + x_offset, y + y_offset);
            },
            .MiddleRight => {
                const x_offset = @max(self.options.width - component_constraints.width, 0);
                const y_offset = @divTrunc(@max(self.options.height - component_constraints.height, 0), 2);

                self.component.render(screen, x + x_offset, y + y_offset);
            },

            .BottomLeft => {
                const y_offset = @max(self.options.height - component_constraints.height, 0);

                self.component.render(screen, x, y + y_offset);
            },
            .BottomMiddle => {
                const x_offset = @divTrunc(@max(self.options.width - component_constraints.width, 0), 2);
                const y_offset = @max(self.options.height - component_constraints.height, 0);

                self.component.render(screen, x + x_offset, y + y_offset);
            },
            .BottomRight => {
                const x_offset = @max(self.options.width - component_constraints.width, 0);
                const y_offset = @max(self.options.height - component_constraints.height, 0);

                self.component.render(screen, x + x_offset, y + y_offset);
            },
        }
    }

    fn to_component(self: *Container) Component {
        return Component{ .ctx = self, .vtable = vtable };
    }

    pub const Options = struct {
        width: usize,
        height: usize,
        alignment: ?Alignment,
    };

    pub const Alignment = enum(u8) {
        TopLeft,
        TopMiddle,
        TopRight,
        MiddleLeft,
        Middle,
        MiddleRight,
        BottomLeft,
        BottomMiddle,
        BottomRight,
    };
};

const Padding = struct {
    const vtable = Component.VTable{
        .constraints = constraints,
        .render = render,
    };

    component: Component,
    options: Options,

    fn init(component: Component, options: Options) Padding {
        return .{
            .component = component,
            .options = options,
        };
    }

    fn constraints(ctx: *const anyopaque) Constraints {
        const self: *const Padding = @ptrCast(@alignCast(ctx));

        const component_constraints: Constraints = self.component.constraints();
        const left, const top, const right, const bottom = self.get_sided();

        return Constraints{
            .width = component_constraints.width + left + right,
            .height = component_constraints.height + top + bottom,
        };
    }

    fn get_sided(self: *const Padding) struct { usize, usize, usize, usize } {
        switch (self.options) {
            .same => |c| {
                return .{ c, c, c, c };
            },
            .sided => |sided| {
                return .{
                    sided.left,
                    sided.top,
                    sided.right,
                    sided.bottom,
                };
            },
        }
    }

    fn render(ctx: *const anyopaque, screen: *Screen, x: usize, y: usize) void {
        const self: *const Padding = @ptrCast(@alignCast(ctx));

        const left, const top, const right, const bottom = self.get_sided();

        const self_constraints: Constraints = self.component.constraints();

        self.component.render(screen, x + left, y + top);

        for (0..top) |y_offset| {
            for (0..self_constraints.width + left + right) |i| {
                screen.setChar(x + i, y + y_offset, Char.empty());
            }
        }

        for (0..self_constraints.height) |i| {
            for (0..left) |x_offset| {
                screen.setChar(x + x_offset, y + top + i, Char.empty());
            }

            for (0..right) |x_offset| {
                screen.setChar(x + left + self_constraints.width + x_offset, y + top + i, Char.empty());
            }
        }

        for (0..bottom) |y_offset| {
            for (0..self_constraints.width + left + right) |i| {
                screen.setChar(x + i, y + top + self_constraints.height + y_offset, Char.empty());
            }
        }
    }

    fn to_component(self: *Padding) Component {
        return Component{ .ctx = self, .vtable = vtable };
    }

    pub const Options = union(enum) {
        same: usize,
        sided: struct {
            left: usize,
            top: usize,
            right: usize,
            bottom: usize,
        },
    };
};

const Border = struct {
    const vtable = Component.VTable{
        .constraints = constraints,
        .render = render,
    };

    component: Component,
    options: Options,

    fn init(component: Component, options: Options) Border {
        return .{
            .component = component,
            .options = options,
        };
    }

    fn constraints(ctx: *const anyopaque) Constraints {
        const self: *const Border = @ptrCast(@alignCast(ctx));

        const component_constraints: Constraints = self.component.constraints();
        return Constraints{
            .width = component_constraints.width + 2,
            .height = component_constraints.height + 2,
        };
    }

    fn render(ctx: *const anyopaque, screen: *Screen, x: usize, y: usize) void {
        const self: *const Border = @ptrCast(@alignCast(ctx));

        const left, const top, const right, const bottom = blk: {
            switch (self.options) {
                .char => |c| {
                    break :blk .{ c, c, c, c };
                },
                .sided => |sided| {
                    break :blk .{
                        sided.left,
                        sided.top,
                        sided.right,
                        sided.bottom,
                    };
                },
            }
        };

        const self_constraints: Constraints = self.component.constraints();
        self.component.render(screen, x + 1, y + 1);

        for (0..self_constraints.width + 2) |i| {
            screen.setChar(x + i, y, Char.fromChar(top));
        }

        for (0..self_constraints.height) |i| {
            screen.setChar(x, y + 1 + i, Char.fromChar(left));
            screen.setChar(x + 1 + self_constraints.width, y + 1 + i, Char.fromChar(right));
        }

        for (0..self_constraints.width + 2) |i| {
            screen.setChar(x + i, y + 1 + self_constraints.height, Char.fromChar(bottom));
        }
    }

    fn to_component(self: *Border) Component {
        return Component{ .ctx = self, .vtable = vtable };
    }

    pub const Options = union(enum) {
        char: u8,
        sided: struct {
            top: u8,
            left: u8,
            bottom: u8,
            right: u8,
        },
    };
};

const Constraints = struct {
    width: usize,
    height: usize,
};

const Text = struct {
    const vtable = Component.VTable{
        .constraints = constraints,
        .render = render,
    };

    value: []u8,
    max_chars: usize,

    fn init(text: []u8, max_chars: usize) Text {
        return .{
            .value = text,
            .max_chars = max_chars,
        };
    }

    fn constraints(ctx: *const anyopaque) Constraints {
        const self: *const Text = @ptrCast(@alignCast(ctx));

        return Constraints{
            .width = self.max_chars,
            .height = 1,
        };
    }

    fn render(ctx: *const anyopaque, screen: *Screen, x: usize, y: usize) void {
        const self: *const Text = @ptrCast(@alignCast(ctx));

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

                screen.setChar(x + i, y, char);
            } else if (i == self.value.len - 1 or i == self.max_chars - 1) {
                var char = std.mem.zeroes(Char);
                char.data[0] = c;
                char.data[1] = '\x1b';
                char.data[2] = '[';
                char.data[3] = '0';
                char.data[4] = 'm';

                screen.setChar(x + i, y, char);
            } else {
                screen.setChar(x + i, y, Char.fromChar(c));
            }
        }
    }

    fn to_component(self: *Text) Component {
        return Component{ .ctx = self, .vtable = vtable };
    }
};

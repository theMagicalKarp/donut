const std = @import("std");
const vaxis = @import("vaxis");
const math = @import("zlm").as(f64);
const math_usize = @import("zlm").as(usize);

const Shading = @import("./shading.zig").Shading;

const Scene = @import("./scene.zig").Scene;
const Rotate = @import("./geometry/rotate.zig").Rotate;
const Torus = @import("./geometry/torus.zig").Torus;
const UnionSmooth = @import("./geometry/union_smooth.zig").UnionSmooth;
const Sphere = @import("./geometry/sphere.zig").Sphere;
const Scale = @import("./geometry/scale.zig").Scale;

const Geometry = @import("./geometry/geometry.zig").Geometry;

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    focus_in,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var buffer: [1024]u8 = undefined;
    var tty = try vaxis.Tty.init(&buffer);
    defer tty.deinit();

    var screen_buffer = std.io.Writer.Allocating.init(allocator);
    defer screen_buffer.deinit();

    var vx = try vaxis.init(allocator, .{});
    defer vx.deinit(allocator, tty.writer());

    var loop: vaxis.Loop(Event) = .{ .tty = &tty, .vaxis = &vx };
    try loop.init();
    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty.writer());
    try vx.queryTerminal(tty.writer(), 1 * std.time.ns_per_s);

    const gamma: f32 = 2.4;
    const light_position = math.vec3(1.0, -1.0, -1.0).normalize();

    const t1 = Geometry{ .torus = .{ .inner = 0.2, .outer = 1.0 } };
    const rt1 = Geometry{ .rotate = Rotate.new(&t1, math.vec3(0.0, 0.0, 1.0), 90.0) };
    const t2 = Geometry{ .torus = .{ .inner = 0.2, .outer = 1.0 } };
    const t3 = Geometry{ .union_smooth = .{ .a = &rt1, .b = &t2, .smooth = 0.3 } };
    const st3 = Geometry{ .scale = .{ .geometry = &t3, .amount = 1.2 } };

    const GeometryScene = Scene(Geometry);
    const shading = Shading.new(light_position, gamma);

    var some_scene: ?GeometryScene = null;

    while (true) {
        while (loop.tryEvent()) |event| {
            switch (event) {
                .key_press => |key| {
                    if (key.matches('c', .{ .ctrl = true })) {
                        return;
                    } else if (key.matches('q', .{})) {
                        return;
                    }
                },

                .winsize => |ws| {
                    try vx.resize(allocator, tty.writer(), ws);
                    some_scene = GeometryScene.new(math_usize.vec2(ws.cols - 2, ws.rows - 2), shading);
                },
                else => {},
            }
        }

        const win = vx.window();
        win.clear();

        const child = win.child(.{
            .x_off = 0,
            .y_off = 0,
            .width = win.width,
            .height = win.height,
            .border = .{
                .where = .all,
                .style = .{
                    .fg = .{ .index = 5 },
                },
            },
        });

        screen_buffer.clearRetainingCapacity();
        if (some_scene) |scene| {
            try scene.render(0.0, st3, &screen_buffer.writer);
            _ = child.printSegment(.{ .text = screen_buffer.written() }, .{ .wrap = .grapheme });
        }

        try vx.render(tty.writer());
        std.Thread.sleep(30 * std.time.ns_per_ms);
    }
}

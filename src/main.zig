const std = @import("std");
const vaxis = @import("vaxis");
const math = @import("zlm").as(f64);
const math_usize = @import("zlm").as(usize);

const Shading = @import("./shading.zig").Shading;
const Scene = @import("./scene.zig").Scene;
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

    const donut = Geometry{ .torus = .{
        .inner = 0.2,
        .outer = 1.0,
    } };
    const donut2 = Geometry{ .rotatez = .{ .geometry = &donut, .angle = 45.0 } };

    const box = Geometry{ .box = .{ .dimensions = math.vec3(0.5, 0.5, 0.5) } };
    _ = box;

    const repeat = Geometry{
        .repeat = .{ .geometry = &donut, .spacing = 3.0 },
    };
    _ = repeat;

    const g = donut2;

    const GeometryScene = Scene(Geometry);
    const shading = Shading.new(light_position, gamma);

    var some_scene: ?GeometryScene = null;

    const cam_right = math.vec3(1.0, 0.0, 0.0);
    const cam_up = math.vec3(0.0, 1.0, 0.0);
    var t: f64 = 0.0;
    var roty: f64 = 0.0;
    var rotx: f64 = 0.0;

    while (true) {
        while (loop.tryEvent()) |event| {
            switch (event) {
                .key_press => |key| {
                    if (key.matches('c', .{ .ctrl = true })) {
                        return;
                    } else if (key.matches('q', .{})) {
                        return;
                    } else if (key.matches('a', .{})) {
                        roty = roty + 0.05;
                    } else if (key.matches('d', .{})) {
                        roty = roty - 0.05;
                    } else if (key.matches('w', .{})) {
                        rotx = rotx + 0.05;
                    } else if (key.matches('s', .{})) {
                        rotx = rotx - 0.05;
                    }
                },

                .winsize => |ws| {
                    try vx.resize(allocator, tty.writer(), ws);
                    some_scene = GeometryScene.new(
                        math_usize.vec2(ws.cols - 2, ws.rows - 2),
                        shading,
                    );
                },
                else => {},
            }
        }

        t = t + 0.1;

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
            const rot_y = math.Mat4.createAngleAxis(cam_up, roty);
            const rot_x = math.Mat4.createAngleAxis(cam_right, rotx);
            const rot_cam_rel = rot_y.mul(rot_x);

            // Apply rotation to geometry
            const rotated = Geometry{
                .transform = .{
                    .geometry = &g,
                    .matrix = rot_cam_rel.transpose(),
                },
            };

            try scene.render(
                t,
                rotated,
                &screen_buffer.writer,
            );

            _ = child.printSegment(
                .{ .text = screen_buffer.written() },
                .{ .wrap = .grapheme },
            );
        }

        try vx.render(tty.writer());
        std.Thread.sleep(30 * std.time.ns_per_ms);
    }
}

const std = @import("std");
const vaxis = @import("vaxis");
const math = @import("zlm").as(f64);
const math_usize = @import("zlm").as(usize);

const Shading = @import("./shading.zig").Shading;
const Scene = @import("./scene.zig").Scene;
const Camera = @import("./camera.zig").Camera;
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

    var scroll_buffer_x = std.io.Writer.Allocating.init(allocator);
    defer scroll_buffer_x.deinit();

    var scroll_buffer_y = std.io.Writer.Allocating.init(allocator);
    defer scroll_buffer_y.deinit();

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

    const sphere = Geometry{ .sphere = .{ .radius = 0.25 } };
    const bouncing_sphere = Geometry{ .lerp = .{
        .geometry = &sphere,
        .start = math.vec3(0.0, 0.0, 3.0),
        .stop = math.vec3(0.0, 0.0, -3.0),
        .time_scale = 4000.0,
        .ease = .smoother,
        .mode = .ping_pong,
    } };
    const box = Geometry{ .box = .{ .dimensions = math.vec3(0.6, 0.6, 0.6) } };
    const box_spinz = Geometry{ .spinz = .{ .geometry = &box, .rate = 0.001 } };
    const box_spinx = Geometry{ .spinx = .{ .geometry = &box_spinz, .rate = 0.001 } };

    const g1 = Geometry{
        .union_smooth = .{ .a = &bouncing_sphere, .b = &box_spinx, .smooth = 2.0 },
    };

    const donut = Geometry{ .torus = .{
        .inner = 0.2,
        .outer = 1.0,
    } };

    const repeat = Geometry{
        .repeat = .{ .geometry = &box, .spacing = 2.0 },
    };

    const bounce = Geometry{ .lerp = .{
        .geometry = &donut,
        .start = math.vec3(0.0, 0.0, 1.0),
        .stop = math.vec3(0.0, 0.0, -1.0),
        .time_scale = 2000.0,
        .ease = .smoother,
        .mode = .ping_pong,
    } };

    // _ = box;
    _ = repeat;
    // _ = donut;
    _ = bounce;

    // const g = repeat;
    // const g = bouncing_sphere;
    // const g = g1;
    const g = g1;

    const GeometryScene = Scene(Geometry);
    const shading = Shading.new(light_position, gamma);
    const scene = GeometryScene.new(shading);

    var camera_distance: f64 = 2.0;
    var camera_theta: f64 = 0.0;
    var camera_phi: f64 = 1.57;

    var camera = Camera{
        .position = Camera.orbit(
            math.vec3(0.0, 0.0, 0.0),
            camera_distance,
            camera_theta,
            camera_phi,
        ),
        .resolution = math_usize.vec2(0, 0),
        .look_at = math.vec3(0.0, 0.0, 0.0),
    };
    const start = std.time.milliTimestamp();

    while (true) {
        while (loop.tryEvent()) |event| {
            switch (event) {
                .key_press => |key| {
                    if (key.matches('c', .{ .ctrl = true })) {
                        return;
                    } else if (key.matches('q', .{})) {
                        return;
                    } else if (key.matches('a', .{})) {
                        camera_theta = camera_theta + 0.05;
                        camera.position = Camera.orbit(
                            camera.look_at,
                            camera_distance,
                            camera_theta,
                            camera_phi,
                        );
                    } else if (key.matches('d', .{})) {
                        camera_theta = camera_theta - 0.05;

                        camera.position = Camera.orbit(
                            camera.look_at,
                            camera_distance,
                            camera_theta,
                            camera_phi,
                        );
                    } else if (key.matches('w', .{})) {
                        camera_phi = std.math.clamp(camera_phi - 0.05, 0.1, 3.04);
                        camera.position = Camera.orbit(
                            camera.look_at,
                            camera_distance,
                            camera_theta,
                            camera_phi,
                        );
                    } else if (key.matches('s', .{})) {
                        camera_phi = std.math.clamp(camera_phi + 0.05, 0.1, 3.04);
                        camera.position = Camera.orbit(
                            camera.look_at,
                            camera_distance,
                            camera_theta,
                            camera_phi,
                        );
                    } else if (key.matches('r', .{})) {
                        camera_theta = 0.0;
                        camera_phi = 1.57;
                        camera.position = Camera.orbit(
                            camera.look_at,
                            camera_distance,
                            camera_theta,
                            camera_phi,
                        );
                    } else if (key.matches('z', .{ .shift = false })) {
                        camera_distance = camera_distance - 0.05;
                        camera.position = Camera.orbit(
                            camera.look_at,
                            camera_distance,
                            camera_theta,
                            camera_phi,
                        );
                    } else if (key.matches('z', .{ .shift = true })) {
                        camera_distance = camera_distance + 0.05;
                        camera.position = Camera.orbit(
                            camera.look_at,
                            camera_distance,
                            camera_theta,
                            camera_phi,
                        );
                    }
                },

                .winsize => |ws| {
                    try vx.resize(allocator, tty.writer(), ws);
                    camera.resolution = math_usize.vec2(ws.cols - 2, ws.rows - 2);
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

        try scene.render(
            @floatFromInt(start - std.time.milliTimestamp()),
            camera,
            g,
            &screen_buffer.writer,
        );

        _ = child.printSegment(
            .{ .text = screen_buffer.written() },
            .{ .wrap = .grapheme },
        );

        _ = win.child(.{
            .x_off = win.width / 2 - 2,
            .y_off = 0,
            .width = 25,
            .height = 1,
        }).printSegment(
            .{ .text = " demo ", .style = .{
                .bold = true,
                .fg = .{ .index = 4 },
            } },
            .{ .wrap = .grapheme },
        );

        scroll_buffer_x.clearRetainingCapacity();
        const x_progress: i32 = @intFromFloat(
            @mod(std.math.pi - camera_theta, std.math.tau) / std.math.tau * @as(f64, @floatFromInt(win.width - 2)),
        );
        for (0..win.width - 2) |i| {
            if (i == x_progress) {
                _ = try scroll_buffer_x.writer.write("▲");
            } else {
                _ = try scroll_buffer_x.writer.write(" ");
            }
        }

        _ = win.child(.{
            .x_off = 1,
            .y_off = 1,
            .width = win.width - 2,
            .height = 1,
        }).printSegment(
            .{ .text = scroll_buffer_x.written(), .style = .{
                .bold = true,
                .fg = .{ .index = 4 },
            } },
            .{ .wrap = .grapheme },
        );

        scroll_buffer_y.clearRetainingCapacity();

        const y_progress: i32 = @intFromFloat(
            @mod(camera_phi - 0.1, 3.04) / 3.04 * @as(f64, @floatFromInt(win.height - 2)),
        );

        for (0..win.height - 2) |i| {
            if (i == y_progress) {
                _ = try scroll_buffer_y.writer.write("◀");
            } else {
                _ = try scroll_buffer_y.writer.write(" ");
            }
        }

        _ = win.child(.{
            .x_off = 1,
            .y_off = 1,
            .width = 1,
            .height = win.height - 2,
        }).printSegment(
            .{ .text = scroll_buffer_y.written(), .style = .{
                .bold = true,
                .fg = .{ .index = 4 },
            } },
            .{ .wrap = .grapheme },
        );

        try vx.render(tty.writer());
        std.Thread.sleep(30 * std.time.ns_per_ms);
    }
}

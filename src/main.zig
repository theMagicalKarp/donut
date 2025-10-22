const std = @import("std");
const vaxis = @import("vaxis");
const math = @import("zlm").as(f64);
const math_usize = @import("zlm").as(usize);

const Shading = @import("./shading.zig").Shading;
const Scene = @import("./scene.zig").Scene;
const Camera = @import("./camera.zig").Camera;
const Geometry = @import("./geometry/geometry.zig").Geometry;
const FrameSync = @import("./frame_sync.zig").FrameSync;

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    focus_in,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var fps_buffer = std.io.Writer.Allocating.init(allocator);
    defer fps_buffer.deinit();

    var scene_buffer = std.io.Writer.Allocating.init(allocator);
    defer scene_buffer.deinit();

    var scroll_buffer_x = std.io.Writer.Allocating.init(allocator);
    defer scroll_buffer_x.deinit();

    var scroll_buffer_y = std.io.Writer.Allocating.init(allocator);
    defer scroll_buffer_y.deinit();

    var tty_buffer: [1024]u8 = undefined;
    var tty = try vaxis.Tty.init(&tty_buffer);
    defer tty.deinit();

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

    const g1 = Geometry{
        .union_smooth = .{
            .a = &Geometry{
                .lerp = .{
                    .geometry = &Geometry{ .sphere = .{ .radius = 0.25 } },
                    .start = math.vec3(0.0, 0.0, 3.0),
                    .stop = math.vec3(0.0, 0.0, -3.0),
                    .time_scale = 4000.0,
                    .ease = .smoother,
                    .mode = .ping_pong,
                },
            },
            .b = &Geometry{
                .spinx = .{
                    .geometry = &Geometry{
                        .spinz = .{
                            .geometry = &Geometry{
                                .box = .{ .dimensions = math.vec3(0.6, 0.6, 0.6) },
                            },
                            .rate = 0.001,
                        },
                    },
                    .rate = 0.001,
                },
            },
            .smooth = 2.0,
        },
    };

    const donut = Geometry{ .torus = .{
        .inner = 0.2,
        .outer = 1.0,
    } };

    // const repeat = Geometry{
    //     .repeat = .{ .geometry = &box, .spacing = 2.0 },
    // };

    const bounce = Geometry{ .lerp = .{
        .geometry = &donut,
        .start = math.vec3(0.0, 0.0, 1.0),
        .stop = math.vec3(0.0, 0.0, -1.0),
        .time_scale = 2000.0,
        .ease = .smoother,
        .mode = .ping_pong,
    } };

    // _ = box;
    // _ = repeat;
    // _ = donut;
    _ = bounce;

    // const g = repeat;
    // const g = bouncing_sphere;
    // const g = g1;
    const g = g1;

    const GeometryScene = Scene(Geometry);
    const shading = Shading.new(light_position, gamma);
    const scene = GeometryScene.new(shading);

    var paused: bool = false;
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
    var total_time: u64 = 0;
    var timer = try std.time.Timer.start();
    var frame_sync = try FrameSync.new(30.0);

    while (true) {
        frame_sync.start();
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
                        camera_distance = 2.0;
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
                    } else if (key.matches(' ', .{})) {
                        paused = !paused;
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

        if (!paused) {
            total_time = total_time + timer.lap() / std.time.ns_per_ms;
        } else {
            timer.reset();
        }

        try render_scene(
            win,
            &scene_buffer,
            scene,
            camera,
            g,
            @floatFromInt(total_time),
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

        try render_x_scroll(
            win,
            &scroll_buffer_x,
            @mod(std.math.pi - camera_theta, std.math.tau) / std.math.tau,
        );

        try render_y_scroll(
            win,
            &scroll_buffer_y,
            @mod(camera_phi - 0.1, 3.04) / 3.04,
        );

        try render_fps(win, &fps_buffer, frame_sync);

        try vx.render(tty.writer());
        frame_sync.end();
        frame_sync.wait();
    }
}

fn render_scene(win: vaxis.Window, buffer: *std.io.Writer.Allocating, scene: Scene(Geometry), camera: Camera, geometry: Geometry, time: f64) !void {
    buffer.clearRetainingCapacity();

    try scene.render(
        time,
        camera,
        geometry,
        &buffer.writer,
    );

    _ = win.child(.{
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
    }).printSegment(
        .{ .text = buffer.written() },
        .{ .wrap = .grapheme },
    );
}

fn render_fps(win: vaxis.Window, buffer: *std.io.Writer.Allocating, frame_sync: FrameSync) !void {
    buffer.clearRetainingCapacity();
    try buffer.writer.print("FPS: {d:.2}\n", .{frame_sync.measured_fps});

    _ = win.child(.{
        .x_off = 4,
        .y_off = win.height - 1,
        .width = 16,
        .height = 1,
    }).printSegment(
        .{ .text = buffer.written(), .style = .{
            .bold = true,
            .fg = .{ .index = 5 },
        } },
        .{ .wrap = .grapheme },
    );
}

fn render_x_scroll(win: vaxis.Window, buffer: *std.io.Writer.Allocating, percentage: f64) !void {
    buffer.clearRetainingCapacity();
    const progress: i32 = @intFromFloat(
        percentage * @as(f64, @floatFromInt(win.width - 2)),
    );

    for (0..win.width - 2) |i| {
        if (i == progress) {
            _ = try buffer.writer.write("▲");
        } else {
            _ = try buffer.writer.write(" ");
        }
    }

    _ = win.child(.{
        .x_off = 1,
        .y_off = 1,
        .width = win.width - 2,
        .height = 1,
    }).printSegment(
        .{ .text = buffer.written(), .style = .{
            .bold = true,
            .fg = .{ .index = 4 },
        } },
        .{ .wrap = .grapheme },
    );
}

fn render_y_scroll(win: vaxis.Window, buffer: *std.io.Writer.Allocating, percentage: f64) !void {
    buffer.clearRetainingCapacity();

    const progress: i32 = @intFromFloat(
        percentage * @as(f64, @floatFromInt(win.height - 2)),
    );

    for (0..win.height - 2) |i| {
        if (i == progress) {
            _ = try buffer.writer.write("◀");
        } else {
            _ = try buffer.writer.write(" ");
        }
    }

    _ = win.child(.{
        .x_off = 1,
        .y_off = 1,
        .width = 1,
        .height = win.height - 2,
    }).printSegment(
        .{ .text = buffer.written(), .style = .{
            .bold = true,
            .fg = .{ .index = 4 },
        } },
        .{ .wrap = .grapheme },
    );
}

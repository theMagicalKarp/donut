const std = @import("std");
const vaxis = @import("vaxis");
const math = @import("zlm").as(f64);
const math_usize = @import("zlm").as(usize);

const donut = @import("donut");

const clock: std.Io.Clock = .awake;

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    focus_in,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var title_buffer = std.Io.Writer.Allocating.init(allocator);
    defer title_buffer.deinit();

    var fps_buffer = std.Io.Writer.Allocating.init(allocator);
    defer fps_buffer.deinit();

    var position_buffer = std.Io.Writer.Allocating.init(allocator);
    defer position_buffer.deinit();

    var scene_buffer = std.Io.Writer.Allocating.init(allocator);
    defer scene_buffer.deinit();

    var tty_buffer: [1024]u8 = undefined;
    var tty = try vaxis.Tty.init(io, &tty_buffer);
    defer tty.deinit();

    var vx = try vaxis.init(io, allocator, init.environ_map, .{});
    defer vx.deinit(allocator, tty.writer());

    var loop: vaxis.Loop(Event) = .init(io, &tty, &vx);
    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty.writer());
    try vx.queryTerminal(tty.writer(), .fromSeconds(1));

    const gamma: f32 = 2.4;
    const light_position = math.vec3(1.0, -1.0, -1.0).normalize();

    var geometry_index: usize = 0;
    const titles = [_][]const u8{
        "Donut",
        "Morph",
        "The Spinz",
        "Marching Octahedrons",
    };

    const geometry: []const donut.Geometry = &.{
        .{
            .spinx = .{
                .geometry = &.{
                    .spinz = .{
                        .geometry = &.{
                            .translate = .{
                                .geometry = &.{ .torus = .{ .inner = 0.45, .outer = 1.0 } },
                                .direction = math.vec3(0.0, 0.05, 0.0),
                            },
                        },
                        .rate = 0.002,
                    },
                },
                .rate = 0.001,
            },
        },
        .{
            .union_smooth = .{
                .a = &.{
                    .lerp = .{
                        .geometry = &.{ .sphere = .{ .radius = 0.25 } },
                        .start = math.vec3(0.0, 0.0, 3.0),
                        .stop = math.vec3(0.0, 0.0, -3.0),
                        .time_scale = 4000.0,
                        .ease = .smoother,
                        .mode = .ping_pong,
                    },
                },
                .b = &.{
                    .spinx = .{
                        .geometry = &.{
                            .spinz = .{
                                .geometry = &.{
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
        },
        .{
            .union_exact = .{
                .a = &.{
                    .union_exact = .{
                        .a = &.{
                            .rotatex = .{
                                .geometry = &.{
                                    .spiny = .{
                                        .geometry = &.{
                                            .translate = .{
                                                .geometry = &.{ .sphere = .{ .radius = 0.15 } },
                                                .direction = math.vec3(0.0, 0.0, 1.5),
                                            },
                                        },
                                        .rate = 0.0025,
                                    },
                                },
                                .angle = 0.25,
                            },
                        },
                        .b = &.{
                            .time_offset = .{
                                .geometry = &.{
                                    .rotatex = .{
                                        .geometry = &.{
                                            .spiny = .{
                                                .geometry = &.{
                                                    .translate = .{
                                                        .geometry = &.{ .sphere = .{ .radius = 0.15 } },
                                                        .direction = math.vec3(0.0, 0.0, 1.5),
                                                    },
                                                },
                                                .rate = 0.0025,
                                            },
                                        },
                                        .angle = 45.0,
                                    },
                                },
                                .duration = 1000.0,
                            },
                        },
                    },
                },
                .b = &.{
                    .union_exact = .{
                        .a = &.{
                            .time_offset = .{
                                .geometry = &.{
                                    .rotatex = .{
                                        .geometry = &.{
                                            .spiny = .{
                                                .geometry = &.{
                                                    .translate = .{
                                                        .geometry = &.{ .sphere = .{ .radius = 0.15 } },
                                                        .direction = math.vec3(0.0, 0.0, 1.5),
                                                    },
                                                },
                                                .rate = 0.0025,
                                            },
                                        },
                                        .angle = 90.0,
                                    },
                                },
                                .duration = 1500.0,
                            },
                        },
                        .b = &.{
                            .spinx = .{
                                .geometry = &.{
                                    .spinz = .{
                                        .geometry = &.{
                                            .translate = .{
                                                .geometry = &.{
                                                    .box = .{ .dimensions = math.vec3(0.6, 0.6, 0.6) },
                                                },
                                                .direction = math.vec3(0.0, 0.05, 0.0),
                                            },
                                        },
                                        .rate = 0.002,
                                    },
                                },
                                .rate = 0.001,
                            },
                        },
                    },
                },
            },
        },
        .{
            .walk = .{
                .geometry = &.{
                    .repeat = .{
                        .geometry = &.{
                            .spinx = .{
                                .geometry = &.{ .octahedron = .{ .size = 0.25 } },
                                .rate = 0.001,
                            },
                        },
                        .spacing = 1.0,
                    },
                },
                .direction = math.vec3(0.00025, 0.0, 0.0),
            },
        },
    };

    const scene = donut.Scene(donut.Geometry).new(
        donut.Shading.new(light_position, gamma),
    );

    var paused: bool = false;
    var camera_distance = donut.Interval(f64){
        .current = 2.0,
        .default = 2.0,
        .min = 0.1,
        .max = 10.0,
        .step = 0.1,
    };
    var camera_theta = donut.Interval(f64){
        .current = 0.0,
        .default = 0.0,
        .min = -std.math.floatMax(f64),
        .max = std.math.floatMax(f64),
        .step = 0.1,
    };
    var camera_phi = donut.Interval(f64){
        .current = 1.57,
        .default = 1.57,
        .min = 0.1,
        .max = 3.04,
        .step = 0.1,
    };

    var camera = donut.Camera{
        .position = donut.Camera.orbit(
            math.vec3(0.0, 0.0, 0.0),
            camera_distance.current,
            camera_theta.current,
            camera_phi.current,
        ),
        .resolution = math_usize.vec2(0, 0),
        .look_at = math.vec3(0.0, 0.0, 0.0),
    };
    var total_time: u64 = 0;
    var last_tick = clock.now(io);
    var frame_sync = donut.FrameSync.new(io, 30.0);

    while (true) {
        frame_sync.start();
        while (try loop.tryEvent()) |event| {
            switch (event) {
                .key_press => |key| {
                    if (key.matches('c', .{ .ctrl = true })) {
                        return;
                    } else if (key.matches('q', .{})) {
                        return;
                    } else if (key.matches('a', .{})) {
                        camera.position = donut.Camera.orbit(
                            camera.look_at,
                            camera_distance.current,
                            camera_theta.increment(),
                            camera_phi.current,
                        );
                    } else if (key.matches('d', .{})) {
                        camera.position = donut.Camera.orbit(
                            camera.look_at,
                            camera_distance.current,
                            camera_theta.decrement(),
                            camera_phi.current,
                        );
                    } else if (key.matches('w', .{})) {
                        camera.position = donut.Camera.orbit(
                            camera.look_at,
                            camera_distance.current,
                            camera_theta.current,
                            camera_phi.decrement(),
                        );
                    } else if (key.matches('s', .{})) {
                        camera.position = donut.Camera.orbit(
                            camera.look_at,
                            camera_distance.current,
                            camera_theta.current,
                            camera_phi.increment(),
                        );
                    } else if (key.matches('r', .{})) {
                        paused = false;
                        camera_distance.reset();
                        camera_theta.reset();
                        camera_phi.reset();
                        camera.position = donut.Camera.orbit(
                            camera.look_at,
                            camera_distance.current,
                            camera_theta.current,
                            camera_phi.current,
                        );
                    } else if (key.matches('z', .{ .shift = false })) {
                        camera.position = donut.Camera.orbit(
                            camera.look_at,
                            camera_distance.decrement(),
                            camera_theta.current,
                            camera_phi.current,
                        );
                    } else if (key.matches('z', .{ .shift = true })) {
                        camera.position = donut.Camera.orbit(
                            camera.look_at,
                            camera_distance.increment(),
                            camera_theta.current,
                            camera_phi.current,
                        );
                    } else if (key.matches(' ', .{})) {
                        paused = !paused;
                    } else if (key.matches('t', .{})) {
                        geometry_index = (geometry_index + 1) % geometry.len;
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

        const tick = clock.now(io);
        if (!paused) {
            total_time = total_time + @as(u64, @intCast(@divTrunc(
                last_tick.durationTo(tick).nanoseconds,
                std.time.ns_per_ms,
            )));
        }
        last_tick = tick;

        try render_scene(
            win,
            &scene_buffer,
            scene,
            camera,
            geometry[geometry_index],
            @floatFromInt(total_time),
        );

        const title = titles[geometry_index];
        title_buffer.clearRetainingCapacity();
        try title_buffer.writer.print("({s})", .{title});
        _ = win.child(.{
            .x_off = win.width / 2 - @as(u16, @intCast(title_buffer.written().len)) / 2,
            .y_off = 0,
            .width = 25,
            .height = 1,
        }).printSegment(
            .{ .text = title_buffer.written(), .style = .{
                .bold = true,
                .fg = .{ .index = 5 },
            } },
            .{ .wrap = .grapheme },
        );

        try render_fps(win, &fps_buffer, frame_sync);
        try render_position(win, &position_buffer, camera, camera_distance.current);

        try vx.render(tty.writer());
        try tty.writer().flush();
        frame_sync.end();
        try frame_sync.wait();
    }
}

fn render_scene(win: vaxis.Window, buffer: *std.Io.Writer.Allocating, scene: donut.Scene(donut.Geometry), camera: donut.Camera, geometry: donut.Geometry, time: f64) !void {
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

fn render_fps(win: vaxis.Window, buffer: *std.Io.Writer.Allocating, frame_sync: donut.FrameSync) !void {
    buffer.clearRetainingCapacity();
    try buffer.writer.print("FPS: {d:.2}\n", .{frame_sync.fps});

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

fn render_position(win: vaxis.Window, buffer: *std.Io.Writer.Allocating, camera: donut.Camera, zoom: f64) !void {
    buffer.clearRetainingCapacity();

    try buffer.writer.print(
        "Camera({d:>5.2},{d:>5.2},{d:>5.2},{d:>5.2})",
        .{
            camera.position.x,
            camera.position.y,
            camera.position.z,
            zoom,
        },
    );

    _ = win.child(.{
        .x_off = 20,
        .y_off = win.height - 1,
        .width = 42,
        .height = 1,
    }).printSegment(
        .{ .text = buffer.written(), .style = .{
            .bold = true,
            .fg = .{ .index = 5 },
        } },
        .{ .wrap = .grapheme },
    );
}

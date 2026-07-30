const std = @import("std");
const vaxis = @import("vaxis");
const math_usize = @import("zlm").as(usize);

const donut = @import("donut");

const clock: std.Io.Clock = .awake;

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    focus_in,
};

const usage =
    \\Usage: donut [config.jsonc]
    \\
    \\Ray marches signed distance fields into terminal ASCII. With no argument,
    \\the configuration embedded in the binary is used; see src/default.jsonc for
    \\a commented copy of it.
    \\
    \\Options:
    \\  -h, --help   Print this help and exit
    \\
    \\Keys:
    \\  a / d        Orbit left / right
    \\  w / s        Orbit up / down
    \\  z / Z        Zoom in / out
    \\  r            Reset the camera
    \\  space        Pause
    \\  t            Next scene
    \\  q, Ctrl-C    Quit
    \\
;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    // Everything that can reject the invocation happens before the tty goes into
    // raw mode, so a usage or config error lands in a clean terminal.
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args.deinit();
    _ = args.skip();

    var config_path: ?[]const u8 = null;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            write(io, .stdout, usage);
            return;
        }
        if (config_path != null) {
            write(io, .stderr, "donut: unexpected extra argument\n\n" ++ usage);
            std.process.exit(1);
        }
        config_path = arg;
    }

    var diagnostic: donut.Diagnostic = .{};
    var config = if (config_path) |path|
        donut.Config.fromFile(allocator, io, path, &diagnostic) catch |err|
            configFailed(io, path, err, &diagnostic)
    else
        donut.Config.fromSlice(allocator, donut.default_config, &diagnostic) catch |err|
            configFailed(io, "<built-in default>", err, &diagnostic);
    defer config.deinit();

    const accent: vaxis.Color = .{ .index = config.ui.accent };

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

    var scene_index: usize = 0;

    const scene = donut.Scene(donut.Geometry){
        .shading = config.shading,
        .max_steps = config.render.max_steps,
        .max_distance = config.render.max_distance,
        .surface_distance = config.render.surface_distance,
    };

    var paused: bool = false;
    var camera_distance = config.camera.distance;
    var camera_theta = config.camera.theta;
    var camera_phi = config.camera.phi;

    var camera = donut.Camera{
        .position = donut.Camera.orbit(
            config.camera.look_at,
            camera_distance.current,
            camera_theta.current,
            camera_phi.current,
        ),
        .resolution = math_usize.vec2(0, 0),
        .look_at = config.camera.look_at,
    };
    var total_time: u64 = 0;
    var last_tick = clock.now(io);
    var frame_sync = donut.FrameSync.new(io, config.render.target_fps);

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
                        scene_index = (scene_index + 1) % config.scenes.len;
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
            config.scenes[scene_index].geometry.*,
            @floatFromInt(total_time),
            accent,
        );

        const title = config.scenes[scene_index].name;
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
                .fg = accent,
            } },
            .{ .wrap = .grapheme },
        );

        try render_fps(win, &fps_buffer, frame_sync, accent);
        try render_position(win, &position_buffer, camera, camera_distance.current, accent);

        try vx.render(tty.writer());
        try tty.writer().flush();
        frame_sync.end();
        try frame_sync.wait();
    }
}

fn render_scene(win: vaxis.Window, buffer: *std.Io.Writer.Allocating, scene: donut.Scene(donut.Geometry), camera: donut.Camera, geometry: donut.Geometry, time: f64, accent: vaxis.Color) !void {
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
                .fg = accent,
            },
        },
    }).printSegment(
        .{ .text = buffer.written() },
        .{ .wrap = .grapheme },
    );
}

fn render_fps(win: vaxis.Window, buffer: *std.Io.Writer.Allocating, frame_sync: donut.FrameSync, accent: vaxis.Color) !void {
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
            .fg = accent,
        } },
        .{ .wrap = .grapheme },
    );
}

fn render_position(win: vaxis.Window, buffer: *std.Io.Writer.Allocating, camera: donut.Camera, zoom: f64, accent: vaxis.Color) !void {
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
            .fg = accent,
        } },
        .{ .wrap = .grapheme },
    );
}

fn write(io: std.Io, stream: enum { stdout, stderr }, bytes: []const u8) void {
    var buffer: [256]u8 = undefined;
    const file: std.Io.File = switch (stream) {
        .stdout => .stdout(),
        .stderr => .stderr(),
    };
    var out = file.writerStreaming(io, &buffer);
    out.interface.writeAll(bytes) catch {};
    out.interface.flush() catch {};
}

fn configFailed(
    io: std.Io,
    source: []const u8,
    err: anyerror,
    diagnostic: *const donut.Diagnostic,
) noreturn {
    var buffer: [640]u8 = undefined;
    const detail = diagnostic.message();
    const message = std.fmt.bufPrint(
        &buffer,
        "donut: {s}: {s}\n",
        .{ source, if (detail.len != 0) detail else @errorName(err) },
    ) catch "donut: invalid configuration\n";

    write(io, .stderr, message);
    std.process.exit(1);
}

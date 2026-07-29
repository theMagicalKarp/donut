const std = @import("std");

pub const FrameSync = struct {
    io: std.Io,
    target: std.Io.Duration,
    frame_count: usize,
    fps: f64,
    fps_sample_interval: std.Io.Duration,
    fps_sample_start: std.Io.Timestamp,
    frame_start: std.Io.Timestamp,

    const Self = @This();
    const clock: std.Io.Clock = .awake;

    pub fn new(io: std.Io, target_fps: f64) Self {
        const target: i96 = @intFromFloat(@as(f64, std.time.ns_per_s) / target_fps);
        const now = clock.now(io);
        return Self{
            .io = io,
            .target = .fromNanoseconds(target),
            .frame_count = 0,
            .fps_sample_interval = .fromSeconds(1),
            .fps_sample_start = now,
            .fps = 0.0,
            .frame_start = now,
        };
    }

    pub fn start(self: *Self) void {
        self.frame_start = clock.now(self.io);
    }

    pub fn end(self: *Self) void {
        self.frame_count = self.frame_count + 1;

        const sample_read = self.fps_sample_start.untilNow(self.io, clock);
        if (sample_read.nanoseconds >= self.fps_sample_interval.nanoseconds) {
            self.fps = @as(f64, @floatFromInt(self.frame_count)) * @as(f64, @floatFromInt(self.fps_sample_interval.nanoseconds)) / @as(f64, @floatFromInt(sample_read.nanoseconds));
            self.frame_count = 0;
            self.fps_sample_start = clock.now(self.io);
        }
    }

    pub fn wait(self: *Self) std.Io.Cancelable!void {
        const deadline = self.frame_start.addDuration(self.target).withClock(clock);
        try deadline.wait(self.io);
    }
};

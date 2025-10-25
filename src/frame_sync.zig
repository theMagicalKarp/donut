const std = @import("std");

pub const FrameSync = struct {
    target: u64,
    frame_count: usize,
    fps: f64,
    fps_sample_interval: u64,
    fps_sample_timer: std.time.Timer,
    timer: std.time.Timer,

    const Self = @This();

    pub fn new(target_fps: f64) !Self {
        const target: u64 = @intFromFloat(@as(f64, std.time.ns_per_s) / target_fps);
        return Self{
            .target = target,
            .frame_count = 0,
            .fps_sample_interval = std.time.ns_per_s,
            .fps_sample_timer = try std.time.Timer.start(),
            .fps = 0.0,
            .timer = try std.time.Timer.start(),
        };
    }

    pub fn start(self: *Self) void {
        self.timer.reset();
    }

    pub fn end(self: *Self) void {
        self.frame_count = self.frame_count + 1;

        const sample_read = self.fps_sample_timer.read();
        if (sample_read >= self.fps_sample_interval) {
            self.fps = @as(f64, @floatFromInt(self.frame_count)) * @as(f64, @floatFromInt(self.fps_sample_interval)) / @as(f64, @floatFromInt(sample_read));
            self.frame_count = 0;
            self.fps_sample_timer.reset();
        }
    }

    pub fn wait(self: *Self) void {
        while (self.timer.read() <= self.target) {
            std.Thread.sleep(@min(
                std.time.ns_per_ms,
                self.target - self.timer.read(),
            ));
        }
    }
};

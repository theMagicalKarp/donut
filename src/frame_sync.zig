const std = @import("std");

pub const FrameSync = struct {
    target: u64,
    frame_count: usize,
    sample_interval: u64,
    last_sample: u64,
    measured_fps: f64,
    timer: std.time.Timer,
    frame_start: u64,
    frame_end: u64,

    const Self = @This();

    pub fn new(target_fps: f64) !Self {
        const target: u64 = @intFromFloat(@as(f64, std.time.ns_per_s) / target_fps);
        return Self{
            .target = target,
            .frame_count = 0,
            .sample_interval = std.time.ns_per_s,
            .last_sample = 0.0,
            .measured_fps = 0.0,
            .timer = try std.time.Timer.start(),
            .frame_start = 0,
            .frame_end = 0,
        };
    }

    pub fn start(self: *Self) void {
        self.frame_start = self.timer.read();
    }

    pub fn end(self: *Self) void {
        self.frame_end = self.timer.read();
        self.frame_count = self.frame_count + 1;

        const sample_delta = self.frame_end - self.last_sample;
        if (sample_delta >= self.sample_interval) {
            self.measured_fps = @as(f64, @floatFromInt(self.frame_count)) * @as(f64, @floatFromInt(self.sample_interval)) / @as(f64, @floatFromInt(sample_delta));
            self.frame_count = 0;
            self.last_sample = self.frame_end;
        }
    }

    pub fn wait(self: *Self) void {
        const dt_ns: u64 = self.frame_end - self.frame_start;
        if (dt_ns < self.target) {
            std.Thread.sleep(self.target - dt_ns);
        }
    }
};

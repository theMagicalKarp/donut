const std = @import("std");
const math = @import("zlm").as(f64);
const Geometry = @import("geometry.zig").Geometry;

pub const LerpEase = enum { linear, smooth, smoother };
pub const LerpMode = enum { loop, ping_pong };

pub fn lerpVec3(a: math.Vec3, b: math.Vec3, ease: LerpEase, t_in: f64) math.Vec3 {
    const t = std.math.clamp(t_in, 0.0, 1.0);
    const inter = switch (ease) {
        .linear => t,
        .smooth => t * t * (3.0 - 2.0 * t),
        .smoother => t * t * t * (t * (t * 6.0 - 15.0) + 10.0),
    };
    return a.add(b.sub(a).scale(inter));
}

pub const Lerp = struct {
    geometry: *const Geometry,
    start: math.Vec3,
    stop: math.Vec3,
    time_scale: f64,
    ease: LerpEase,
    mode: LerpMode,

    const Self = @This();

    pub fn distance(self: Self, time: f64, point: math.Vec3) f64 {
        const u = @mod(time, self.time_scale) / self.time_scale;
        const t = switch (self.mode) {
            .loop => u,
            .ping_pong => 1.0 - @abs(1.0 - 2.0 * u),
        };

        const q = lerpVec3(self.start, self.stop, self.ease, t).add(point);
        return self.geometry.distance(time, q);
    }
};

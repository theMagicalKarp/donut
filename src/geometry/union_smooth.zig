const std = @import("std");
const math = @import("zlm").as(f64);
const Geometry = @import("geometry.zig").Geometry;

fn mix(x: f64, y: f64, a: f64) f64 {
    return @mulAdd(f64, a, y - x, x);
}

pub const UnionSmooth = struct {
    smooth: f64,
    a: *const Geometry,
    b: *const Geometry,

    const Self = @This();

    pub fn distance(self: Self, point: math.Vec3) f64 {
        const d1 = self.a.distance(point);
        const d2 = self.b.distance(point);

        const h = std.math.clamp(0.5 + 0.5 * (d2 - d1) / self.smooth, 0.0, 1.0);

        return mix(d2, d1, h) - self.smooth * h * (1.0 - h);
    }
};

const math = @import("zlm").as(f64);
const Geometry = @import("geometry.zig").Geometry;

pub const Scale = struct {
    geometry: *const Geometry,
    amount: f64,

    const Self = @This();

    pub fn distance(self: Self, time: f64, point: math.Vec3) f64 {
        return self.geometry.distance(time, point.scale(1.0 / self.amount)) * self.amount;
    }
};

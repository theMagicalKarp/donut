const math = @import("zlm").as(f64);
const Geometry = @import("geometry.zig").Geometry;

pub const UnionExact = struct {
    a: *const Geometry,
    b: *const Geometry,

    const Self = @This();

    pub fn distance(self: Self, time: f64, point: math.Vec3) f64 {
        return @min(self.a.distance(time, point), self.b.distance(time, point));
    }
};

const math = @import("zlm").as(f64);
const Geometry = @import("geometry.zig").Geometry;

pub const UnionExact = struct {
    a: *const Geometry,
    b: *const Geometry,

    const Self = @This();

    pub fn distance(self: Self, point: math.Vec3) f64 {
        return @min(self.a.distance(point), self.b.distance(point));
    }
};

const math = @import("zlm").as(f64);
const Geometry = @import("geometry.zig").Geometry;

pub const Transform = struct {
    matrix: math.Mat4,
    geometry: *const Geometry,

    const Self = @This();

    pub fn distance(self: Self, point: math.Vec3) f64 {
        return self.geometry.distance(point.transformPosition(self.matrix));
    }
};

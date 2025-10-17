const math = @import("zlm").as(f64);
const Geometry = @import("geometry.zig").Geometry;

pub const Rotate = struct {
    transformation: math.Mat4,
    geometry: *const Geometry,

    const Self = @This();

    pub fn new(geometry: *const Geometry, axis: math.Vec3, angle: f64) Self {
        return Self{
            .geometry = geometry,
            .transformation = math.Mat4.createAngleAxis(axis, angle),
        };
    }

    pub fn distance(self: Self, point: math.Vec3) f64 {
        return self.geometry.distance(point.transformPosition(self.transformation));
    }
};

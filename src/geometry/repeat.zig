const math = @import("zlm").as(f64);
const Geometry = @import("geometry.zig").Geometry;

pub const Repeat = struct {
    geometry: *const Geometry,
    spacing: f64,

    const Self = @This();

    pub fn distance(self: Self, time: f64, point: math.Vec3) f64 {
        const q = math.vec3(
            @mod(point.x, self.spacing) - self.spacing / 2.0,
            @mod(point.y, self.spacing) - self.spacing / 2.0,
            @mod(point.z, self.spacing) - self.spacing / 2.0,
        );
        return self.geometry.distance(time, q);
    }
};

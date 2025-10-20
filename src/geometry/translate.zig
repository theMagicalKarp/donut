const math = @import("zlm").as(f64);
const Geometry = @import("geometry.zig").Geometry;

pub const Translate = struct {
    geometry: *const Geometry,
    direction: math.Vec3,

    const Self = @This();

    pub fn distance(self: Self, time: f64, point: math.Vec3) f64 {
        return self.geometry.distance(time, point.add(self.direction));
    }
};

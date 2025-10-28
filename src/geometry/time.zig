const math = @import("zlm").as(f64);
const Geometry = @import("geometry.zig").Geometry;

pub const TimeOffset = struct {
    geometry: *const Geometry,
    duration: f64,

    const Self = @This();

    pub fn distance(self: Self, time: f64, point: math.Vec3) f64 {
        return self.geometry.distance(time + self.duration, point);
    }
};

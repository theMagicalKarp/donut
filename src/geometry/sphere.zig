const math = @import("zlm").as(f64);

pub const Sphere = struct {
    radius: f64,

    const Self = @This();

    pub fn distance(self: Self, time: f64, point: math.Vec3) f64 {
        _ = time;
        return point.length() - self.radius;
    }
};

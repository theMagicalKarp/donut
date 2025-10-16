const math = @import("zlm").as(f64);

pub const Sphere = struct {
    radius: f64,

    const Self = @This();

    pub fn distance(self: Self, point: math.Vec3) f64 {
        return point.length() - self.radius;
    }
};

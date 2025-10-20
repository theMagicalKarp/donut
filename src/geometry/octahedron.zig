const math = @import("zlm").as(f64);

pub const Octahedron = struct {
    size: f64,

    const Self = @This();

    pub fn distance(self: Self, time: f64, point: math.Vec3) f64 {
        _ = time;
        const abs_point = point.abs();
        return (abs_point.x + abs_point.y + abs_point.z - self.size) * 0.57735027;
    }
};

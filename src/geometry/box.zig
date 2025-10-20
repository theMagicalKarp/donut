const math = @import("zlm").as(f64);

pub const Box = struct {
    dimensions: math.Vec3,

    const Self = @This();

    pub fn distance(self: Self, time: f64, point: math.Vec3) f64 {
        _ = time;
        const q = point.abs().sub(self.dimensions);

        return math.vec3(
            @max(q.x, 0.0),
            @max(q.y, 0.0),
            @max(q.z, 0.0),
        ).length() + @min(@max(q.x, @max(q.y, q.z)), 0.0);
    }
};

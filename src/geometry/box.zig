const math = @import("zlm").as(f64);

pub const Octahedron = struct {
    dimensions: math.vec3,

    const Self = @This();

    pub fn distance(self: Self, point: math.Vec3) f64 {
        const q = point.abs().sub(self.dimensions);

        return math.vec3(
            @max(q.x, 0.0),
            @max(q.y, 0.0),
            @max(q.z, 0.0),
        ).length() + @min(@max(q.x, @max(q.y, q.z)), 0.0);
    }
};

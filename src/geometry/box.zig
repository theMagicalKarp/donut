const math = @import("zlm").as(f64);

pub const Box = struct {
    dimensions: math.Vec3,

    const Self = @This();

    pub fn distance(self: Self, time: f64, point: math.Vec3) f64 {
        _ = time;
        const q = point.abs().sub(self.dimensions);

        return q.componentMax(math.Vec3.zero).length() + @min(@max(q.x, @max(q.y, q.z)), 0.0);
    }
};

pub const BoxFrame = struct {
    dimensions: math.Vec3,
    thickness: f64,

    const Self = @This();

    pub fn distance(self: Self, time: f64, point: math.Vec3) f64 {
        _ = time;

        const p = point.abs().sub(self.dimensions);
        const q = p.add(math.Vec3.all(self.thickness)).abs().sub(math.Vec3.all(self.thickness));

        return @min(
            math.vec3(p.x, q.y, q.z).componentMax(math.Vec3.zero).add(math.Vec3.all(@min(@max(p.x, q.y, q.z), 0.0))).length(),
            math.vec3(q.x, p.y, q.z).componentMax(math.Vec3.zero).add(math.Vec3.all(@min(@max(q.x, p.y, q.z), 0.0))).length(),
            math.vec3(q.x, q.y, p.z).componentMax(math.Vec3.zero).add(math.Vec3.all(@min(@max(q.x, q.y, p.z), 0.0))).length(),
        );
    }
};

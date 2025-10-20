const math = @import("zlm").as(f64);

pub const Torus = struct {
    inner: f64,
    outer: f64,

    const Self = @This();

    pub fn distance(self: Self, time: f64, point: math.Vec3) f64 {
        _ = time;
        var q = math.vec2(point.swizzle("xz").length() - self.outer, point.y);
        return q.length() - self.inner;
    }
};

const std = @import("std");
const math = @import("zlm").as(f64);
const Geometry = @import("geometry.zig").Geometry;

pub const UnionExact = struct {
    geometry: []const *const Geometry,

    const Self = @This();

    pub fn distance(self: Self, time: f64, point: math.Vec3) f64 {
        // `min` is associative and commutative, so the order children are
        // listed in cannot change the result.
        if (self.geometry.len == 0) {
            return std.math.floatMax(f64);
        }

        var out = self.geometry[0].distance(time, point);
        for (self.geometry[1..]) |child| {
            out = @min(out, child.distance(time, point));
        }
        return out;
    }
};

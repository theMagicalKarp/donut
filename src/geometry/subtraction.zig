const std = @import("std");
const math = @import("zlm").as(f64);
const Geometry = @import("geometry.zig").Geometry;

pub const Subtraction = struct {
    geometry: []const *const Geometry,

    const Self = @This();

    pub fn distance(self: Self, time: f64, point: math.Vec3) f64 {
        // Unlike the other combinators this one is directional: the first child
        // is the solid, every later one is a tool carved out of it. Order is
        // part of the meaning, not an implementation detail.
        if (self.geometry.len == 0) return std.math.floatMax(f64);

        var out = self.geometry[0].distance(time, point);
        for (self.geometry[1..]) |tool| {
            out = @max(out, -tool.distance(time, point));
        }
        return out;
    }
};

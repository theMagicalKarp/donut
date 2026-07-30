const std = @import("std");
const math = @import("zlm").as(f64);
const Geometry = @import("geometry.zig").Geometry;

fn mix(x: f64, y: f64, a: f64) f64 {
    return @mulAdd(f64, a, y - x, x);
}

/// The polynomial smooth minimum. Commutative, but *not* associative — see the
/// note on `distance`.
fn smoothMin(d1: f64, d2: f64, smooth: f64) f64 {
    const h = std.math.clamp(0.5 + 0.5 * (d2 - d1) / smooth, 0.0, 1.0);
    return mix(d2, d1, h) - smooth * h * (1.0 - h);
}

pub const UnionSmooth = struct {
    smooth: f64,
    geometry: []const *const Geometry,

    const Self = @This();

    pub fn distance(self: Self, time: f64, point: math.Vec3) f64 {
        // Blended left to right. `smoothMin` is not associative, so unlike
        // `union_exact` the order children are listed in does affect the
        // surface — reordering a list of three is a visible change.
        if (self.geometry.len == 0) {
            return std.math.floatMax(f64);
        }

        var out = self.geometry[0].distance(time, point);
        for (self.geometry[1..]) |child| {
            out = smoothMin(out, child.distance(time, point), self.smooth);
        }
        return out;
    }
};

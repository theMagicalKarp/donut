const math = @import("zlm").as(f64);

const Box = @import("box.zig").Box;
const Intersection = @import("intersection.zig").Intersection;
const Octahedron = @import("octahedron.zig").Octahedron;
const Rotate = @import("rotate.zig").Rotate;
const Scale = @import("scale.zig").Scale;
const Sphere = @import("sphere.zig").Sphere;
const Subtraction = @import("subtraction.zig").Subtraction;
const Torus = @import("torus.zig").Torus;
const UnionSmooth = @import("union_smooth.zig").UnionSmooth;
const UnionExact = @import("union_exact.zig").UnionExact;

pub const Geometry = union(enum) {
    box: Box,
    intersection: Intersection,
    octahedron: Octahedron,
    rotate: Rotate,
    scale: Scale,
    sphere: Sphere,
    subtraction: Subtraction,
    torus: Torus,
    union_smooth: UnionSmooth,
    union_exact: UnionExact,

    const Self = @This();

    pub fn distance(self: Self, point: math.Vec3) f64 {
        return switch (self) {
            inline else => |payload| payload.distance(point),
        };
    }
};

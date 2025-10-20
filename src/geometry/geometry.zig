const math = @import("zlm").as(f64);

const Box = @import("box.zig").Box;
const Intersection = @import("intersection.zig").Intersection;
const Lerp = @import("lerp.zig").Lerp;
const Octahedron = @import("octahedron.zig").Octahedron;
const Repeat = @import("repeat.zig").Repeat;
const RotateX = @import("rotate.zig").RotateX;
const RotateY = @import("rotate.zig").RotateY;
const RotateZ = @import("rotate.zig").RotateZ;
const Scale = @import("scale.zig").Scale;
const Sphere = @import("sphere.zig").Sphere;
const SpinX = @import("rotate.zig").SpinX;
const SpinY = @import("rotate.zig").SpinY;
const SpinZ = @import("rotate.zig").SpinZ;
const Subtraction = @import("subtraction.zig").Subtraction;
const Torus = @import("torus.zig").Torus;
const Transform = @import("transform.zig").Transform;
const Translate = @import("translate.zig").Translate;
const UnionSmooth = @import("union_smooth.zig").UnionSmooth;
const UnionExact = @import("union_exact.zig").UnionExact;

pub const Geometry = union(enum) {
    box: Box,
    intersection: Intersection,
    lerp: Lerp,
    octahedron: Octahedron,
    repeat: Repeat,
    rotatex: RotateX,
    rotatey: RotateY,
    rotatez: RotateZ,
    scale: Scale,
    sphere: Sphere,
    spinx: SpinX,
    spiny: SpinY,
    spinz: SpinZ,
    subtraction: Subtraction,
    torus: Torus,
    transform: Transform,
    translate: Translate,
    union_smooth: UnionSmooth,
    union_exact: UnionExact,

    const Self = @This();

    pub fn distance(self: Self, time: f64, point: math.Vec3) f64 {
        return switch (self) {
            inline else => |payload| payload.distance(time, point),
        };
    }
};

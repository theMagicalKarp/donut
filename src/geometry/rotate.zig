const math = @import("zlm").as(f64);
const Geometry = @import("geometry.zig").Geometry;

fn rotate_2d(angle: f64) math.Mat2 {
    const s = @sin(angle);
    const c = @cos(angle);
    return math.Mat2{
        .fields = [2][2]f64{
            [2]f64{ c, -s },
            [2]f64{ s, c },
        },
    };
}

pub const RotateX = struct {
    angle: f64,
    geometry: *const Geometry,

    const Self = @This();

    pub fn distance(self: Self, point: math.Vec3) f64 {
        const transformation = point.swizzle("yz").transform(rotate_2d(self.angle));
        return self.geometry.distance(
            math.vec3(point.x, transformation.x, transformation.y),
        );
    }
};

pub const RotateY = struct {
    angle: f64,
    geometry: *const Geometry,

    const Self = @This();

    pub fn distance(self: Self, point: math.Vec3) f64 {
        const transformation = point.swizzle("xz").transform(rotate_2d(self.angle));
        return self.geometry.distance(
            math.vec3(transformation.x, point.y, transformation.y),
        );
    }
};

pub const RotateZ = struct {
    angle: f64,
    geometry: *const Geometry,

    const Self = @This();

    pub fn distance(self: Self, point: math.Vec3) f64 {
        const transformation = point.swizzle("xy").transform(rotate_2d(self.angle));
        return self.geometry.distance(
            math.vec3(transformation.x, transformation.y, point.z),
        );
    }
};

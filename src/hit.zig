const math = @import("zlm").as(f64);

pub const HitRecord = struct {
    normal: math.Vec3,
    hit: bool,
};

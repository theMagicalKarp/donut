const math = @import("zlm").as(f64);
const math_usize = @import("zlm").as(usize);

pub const Camera = struct {
    position: math.Vec3,
    look_at: math.Vec3,
    resolution: math_usize.Vec2,

    pub fn orbit(target: math.Vec3, distance: f64, theta: f64, phi: f64) math.Vec3 {
        return target.add(math.vec3(
            distance * @sin(phi) * @cos(theta),
            distance * @cos(phi),
            distance * @sin(phi) * @sin(theta),
        ));
    }
};

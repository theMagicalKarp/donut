const std = @import("std");
const math = @import("zlm").as(f64);
const math_usize = @import("zlm").as(usize);

const Camera = @import("./camera.zig").Camera;
const HitRecord = @import("./hit.zig").HitRecord;
const Shading = @import("./shading.zig").Shading;

pub fn get_ray_direction(uv: math.Vec2, point: math.Vec3, lookat: math.Vec3, z: f64) math.Vec3 {
    const f = lookat.sub(point).normalize();
    const r = math.vec3(0.0, 1.0, 0.0).cross(f).normalize();
    const u = f.cross(r);
    const c = point.add(f.scale(z));
    const i = c.add(r.scale(uv.x)).add(u.scale(uv.y));
    return i.sub(point).normalize();
}

pub fn Scene(comptime T: type) type {
    return struct {
        const Self = @This();

        shading: Shading,

        max_steps: usize,
        max_distance: f64,
        surface_distance: f64,

        pub fn new(shading: Shading) Self {
            return Self{
                .shading = shading,
                .max_distance = 100.0,
                .surface_distance = 0.01,
                .max_steps = 80,
            };
        }

        pub fn render(self: Self, time: f64, camera: Camera, geometry: T, writer: *std.Io.Writer) !void {
            for (0..camera.resolution.y) |y| {
                for (0..camera.resolution.x) |x| {
                    const xf: f64 = @floatFromInt(x);
                    const yf: f64 = @floatFromInt(y);
                    const hit_record = self.march(time, camera, geometry, xf, yf);
                    try writer.writeByte(self.shading.calculate(math_usize.vec2(x, y), hit_record));
                }
            }
        }

        pub fn march(self: Self, time: f64, camera: Camera, geometry: T, x: f64, y: f64) HitRecord {
            const resolution = math.vec2(
                @floatFromInt(camera.resolution.x),
                @floatFromInt(camera.resolution.y),
            );

            const frag_coord = math.vec4(x + 0.5, y + 0.5, 0.0, 1.0);
            const uv = frag_coord.scale(2.0).swizzle("xy").sub(
                resolution,
            ).div(math.vec2(resolution.y, resolution.y));

            const ray_direction = get_ray_direction(
                uv,
                camera.position,
                camera.look_at,
                1.0,
            );
            var total_distance: f64 = 0.0;
            for (0..self.max_steps) |i| {
                _ = i;
                const point = camera.position.add(ray_direction.scale(total_distance));

                const distance: f64 = @abs(map(time, point, geometry));
                total_distance = total_distance + distance;
                if (distance < self.surface_distance) {
                    return HitRecord{
                        .hit = true,
                        .normal = get_normal(time, point, geometry),
                        .distance = total_distance,
                    };
                }

                if (total_distance > self.max_distance) {
                    return HitRecord{
                        .hit = false,
                        .normal = math.Vec3.zero,
                        .distance = 0.0,
                    };
                }
            }
            return HitRecord{
                .hit = false,
                .normal = math.Vec3.zero,
                .distance = 0.0,
            };
        }

        pub fn get_normal(time: f64, point: math.Vec3, geometry: T) math.Vec3 {
            const distance = map(time, point, geometry);
            const e = math.vec2(0.01, 0.0);

            return math.vec3(
                distance - map(time, point.sub(e.swizzle("xyy")), geometry),
                distance - map(time, point.sub(e.swizzle("yxy")), geometry),
                distance - map(time, point.sub(e.swizzle("yyx")), geometry),
            ).normalize();
        }

        pub fn map(time: f64, point: math.Vec3, geometry: T) f64 {
            return geometry.distance(time, point);
        }
    };
}

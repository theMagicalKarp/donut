const std = @import("std");
const math = @import("zlm").as(f64);

const LUMINANCE = ".,-~:;=!*#$@";

fn bayer4(x: usize, y: usize) u8 {
    const M = [_][4]u8{
        .{ 0, 8, 2, 10 },
        .{ 12, 4, 14, 6 },
        .{ 3, 11, 1, 9 },
        .{ 15, 7, 13, 5 },
    };
    return M[y & 3][x & 3];
}

fn brightnessToCharDither(x: usize, y: usize, b_in: f64, gamma: f64) u8 {
    const lut = LUMINANCE;
    const levels_f: f32 = @floatFromInt(lut.len);

    // 1) Clamp + gamma (linear -> perceptual)
    const b = std.math.clamp(b_in, 0.0, 1.0);
    const g = if (gamma <= 0.0) 1.0 else gamma;
    const b_perc = std.math.pow(f64, b, 1.0 / g);

    // 2) Ordered dithering bias from Bayer (normalize to [0,1))
    //    Add a *tiny* offset proportional to matrix cell; scale by level count.
    const b4f: f64 = @floatFromInt(bayer4(x, y));
    const t = (b4f + 0.5) / 16.0; // [0,1)
    const bias = (t - 0.5) / levels_f; // small symmetric nudge

    // 3) Quantize to nearest glyph index (rounded)
    const v = std.math.clamp(b_perc + bias, 0.0, 1.0);
    var idx: u8 = @intFromFloat(v * (levels_f - 1.0) + 0.5);
    if (idx >= lut.len) idx = lut.len - 1;

    return lut[idx];
}

const HitRecord = struct {
    normal: math.Vec3,
    hit: bool,
};

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

        light: math.Vec3,
        gamma: f64,

        width: usize,
        height: usize,

        widthf: f64,
        heightf: f64,

        pub fn new(width: usize, height: usize, light: math.Vec3, gamma: f64) Self {
            return Self{
                .width = width,
                .height = height,
                .light = light,
                .widthf = @floatFromInt(width),
                .heightf = @floatFromInt(height),
                .gamma = gamma,
            };
        }

        pub fn render(self: Self, time: f64, geometry: T, writer: *std.Io.Writer) !void {
            for (0..self.height) |y| {
                for (0..self.width) |x| {
                    const xf: f64 = @floatFromInt(x);
                    const yf: f64 = @floatFromInt(y);
                    const hit_record = self.march(time, geometry, xf, yf);
                    if (hit_record.hit) {
                        const brightness = @max(0.0, hit_record.normal.normalize().dot(self.light));
                        try writer.writeByte(brightnessToCharDither(x, y, brightness, self.gamma));
                    } else {
                        try writer.writeByte(' ');
                    }
                }
            }
        }

        pub fn march(self: Self, time: f64, geometry: T, x: f64, y: f64) HitRecord {
            const ray_origin = math.vec3(0.0, 0.0, -2.0);

            const frag_coord = math.vec4(x + 0.5, y + 0.5, 0.0, 1.0);
            const uv = frag_coord.scale(2.0).swizzle("xy").sub(math.vec2(self.widthf, self.heightf)).div(math.vec2(self.heightf, self.heightf));

            const ray_direction = get_ray_direction(uv, ray_origin, math.vec3(0.0, 0.0, 0.0), 1.0);
            var total_distance: f64 = 0.0;
            for (0..80) |i| {
                _ = i;
                const point = ray_origin.add(ray_direction.scale(total_distance));

                const distance: f64 = @abs(map(time, point, geometry));
                total_distance = total_distance + distance;
                if (distance < 0.01) {
                    return HitRecord{ .hit = true, .normal = get_normal(time, point, geometry) };
                }

                if (total_distance > 100.0) {
                    return HitRecord{ .hit = false, .normal = math.Vec3.zero };
                }
            }
            return HitRecord{ .hit = false, .normal = math.Vec3.zero };
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
            _ = time;
            return geometry.distance(point);
        }
    };
}

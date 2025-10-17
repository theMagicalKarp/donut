const std = @import("std");
const math = @import("zlm").as(f64);
const math_usize = @import("zlm").as(usize);

const HitRecord = @import("./hit.zig").HitRecord;

const BAYER_INDEX = [4][4]u8{
    .{ 0, 8, 2, 10 },
    .{ 12, 4, 14, 6 },
    .{ 3, 11, 1, 9 },
    .{ 15, 7, 13, 5 },
};

pub const Shading = struct {
    const Self = @This();

    light: math.Vec3,
    gamma: f64,
    lut: []const u8,

    pub fn new(light: math.Vec3, gamma: f64) Self {
        return Self{
            .light = light,
            .gamma = gamma,
            .lut = ".,-~:;=!*#$@",
        };
    }

    pub fn calculate(self: Self, pixel: math_usize.Vec2, hit_record: HitRecord) u8 {
        if (!hit_record.hit) {
            return ' ';
        }

        const brightness: f64 = @max(0.0, hit_record.normal.normalize().dot(self.light));
        const levels_f: f32 = @floatFromInt(self.lut.len);

        // 1) Clamp + gamma (linear -> perceptual)
        const b: f64 = std.math.clamp(brightness, 0.0, 1.0);
        const g: f64 = if (self.gamma <= 0.0) 1.0 else self.gamma;
        const b_perc = std.math.pow(f64, b, 1.0 / g);

        // 2) Ordered dithering bias from Bayer (normalize to [0,1))
        //    Add a *tiny* offset proportional to matrix cell; scale by level count.
        const b4f: f32 = @floatFromInt(BAYER_INDEX[pixel.y & 3][pixel.x & 3]);
        const t: f32 = (b4f + 0.5) / 16.0; // [0,1)
        const bias: f32 = (t - 0.5) / levels_f; // small symmetric nudge

        // 3) Quantize to nearest glyph index (rounded)
        const v: f64 = std.math.clamp(b_perc + bias, 0.0, 1.0);
        const idx: u8 = @intFromFloat(v * (levels_f - 1.0) + 0.5);

        return self.lut[@min(idx, self.lut.len - 1)];
    }
};

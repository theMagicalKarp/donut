const std = @import("std");

pub fn Interval(comptime T: type) type {
    return struct {
        const Self = @This();

        current: T,
        default: T,
        min: T,
        max: T,
        step: T,

        pub fn increment(self: *Self) T {
            self.current = @min(self.current + self.step, self.max);
            return self.current;
        }

        pub fn decrement(self: *Self) T {
            self.current = @max(self.current - self.step, self.min);
            return self.current;
        }

        pub fn reset(self: *Self) void {
            self.current = self.default;
        }
    };
}

test "Interval(i32): literal init wires fields correctly" {
    const I = Interval(i32);
    const it = I{
        .current = 5,
        .default = 5,
        .min = 0,
        .max = 10,
        .step = 2,
    };

    try std.testing.expectEqual(@as(i32, 5), it.current);
    try std.testing.expectEqual(@as(i32, 5), it.default);
    try std.testing.expectEqual(@as(i32, 0), it.min);
    try std.testing.expectEqual(@as(i32, 10), it.max);
    try std.testing.expectEqual(@as(i32, 2), it.step);
}

test "Interval(i32): increment respects step and clamps at max" {
    const I = Interval(i32);
    var it = I{
        .current = 0,
        .default = 0,
        .min = 0,
        .max = 10,
        .step = 7,
    };

    try std.testing.expectEqual(@as(i32, 7), it.increment()); // 0 -> 7
    try std.testing.expectEqual(@as(i32, 10), it.increment()); // 7 -> 10 (clamp)
    try std.testing.expectEqual(@as(i32, 10), it.increment()); // stays clamped
}

test "Interval(i32): decrement respects step and clamps at min" {
    const I = Interval(i32);
    var it = I{
        .current = 10,
        .default = 10,
        .min = 0,
        .max = 10,
        .step = 6,
    };

    try std.testing.expectEqual(@as(i32, 4), it.decrement()); // 10 -> 4
    try std.testing.expectEqual(@as(i32, 0), it.decrement()); // 4 -> 0 (clamp)
    try std.testing.expectEqual(@as(i32, 0), it.decrement()); // stays clamped
}

test "Interval(i32): reset returns to default" {
    const I = Interval(i32);
    var it = I{
        .current = 3,
        .default = 3,
        .min = 0,
        .max = 10,
        .step = 5,
    };

    _ = it.increment(); // 3 -> 8
    try std.testing.expectEqual(@as(i32, 8), it.current);

    it.reset();
    try std.testing.expectEqual(@as(i32, 3), it.current);
}

test "Interval(i32): works with negative ranges" {
    const I = Interval(i32);
    var it = I{
        .current = -5,
        .default = -5,
        .min = -10,
        .max = -2,
        .step = 3,
    };

    try std.testing.expectEqual(@as(i32, -2), it.increment()); // -5 + 3 = -2 (clamp)
    it.reset();
    try std.testing.expectEqual(@as(i32, -8), it.decrement()); // -5 - 3 = -8 (in range)
    try std.testing.expectEqual(@as(i32, -10), it.decrement()); // -11 -> clamp to -10
}

test "Interval(i32): zero step is a no-op for inc/dec" {
    const I = Interval(i32);
    var it = I{
        .current = 4,
        .default = 4,
        .min = 0,
        .max = 10,
        .step = 0,
    };

    try std.testing.expectEqual(@as(i32, 4), it.increment());
    try std.testing.expectEqual(@as(i32, 4), it.decrement());
    it.reset();
    try std.testing.expectEqual(@as(i32, 4), it.current);
}

// Float helper — tiny approx equality
fn expectApproxEq(comptime T: type, a: T, b: T, eps: T) !void {
    const diff = if (a > b) a - b else b - a;
    try std.testing.expect(diff <= eps);
}

test "Interval(f64): increment/decrement with clamping (approx)" {
    const I = Interval(f64);
    var it = I{
        .current = 0.5,
        .default = 0.5,
        .min = 0.0,
        .max = 1.0,
        .step = 0.3,
    };

    try expectApproxEq(f64, it.increment(), 0.8, 1e-9);
    try expectApproxEq(f64, it.increment(), 1.0, 1e-9); // clamp
    try expectApproxEq(f64, it.increment(), 1.0, 1e-9); // still clamped
    try expectApproxEq(f64, it.decrement(), 0.7, 1e-9);
    try expectApproxEq(f64, it.decrement(), 0.4, 1e-9);
    try expectApproxEq(f64, it.decrement(), 0.1, 1e-9);
    try expectApproxEq(f64, it.decrement(), 0.0, 1e-9); // clamp
}

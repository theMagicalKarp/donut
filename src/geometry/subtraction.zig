const math = @import("zlm").as(f64);

pub fn Subtraction(comptime T: type, comptime U: type) type {
    return struct {
        a: T,
        b: U,

        const Self = @This();

        pub fn new(a: T, b: U) Self {
            return Self{ .a = a, .b = b };
        }

        pub fn distance(self: Self, point: math.Vec3) f64 {
            return @max(-self.a.distance(point), self.b.distance(point));
        }
    };
}

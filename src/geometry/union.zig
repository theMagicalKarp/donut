const math = @import("zlm").as(f64);

pub fn Union(comptime T: type, comptime U: type) type {
    return struct {
        a: T,
        b: U,

        const Self = @This();

        pub fn new(a: T, b: U) Self {
            return Self{ .a = a, .b = b };
        }

        pub fn distance(self: Self, point: math.Vec3) f64 {
            return @min(self.a.distance(point), self.b.distance(point));
        }
    };
}

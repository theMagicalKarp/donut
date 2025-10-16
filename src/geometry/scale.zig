const math = @import("zlm").as(f64);

pub fn Scale(comptime T: type) type {
    return struct {
        geometry: T,
        amount: f64,
        amount_inv: f64,

        const Self = @This();

        pub fn new(geometry: T, amount: f64) Self {
            return Self{ .geometry = geometry, .amount = amount, .amount_inv = 1.0 / amount };
        }

        pub fn distance(self: Self, point: math.Vec3) f64 {
            return self.geometry.distance(point.scale(self.amount_inv)) * self.amount;
        }
    };
}

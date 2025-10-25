const std = @import("std");

pub const Interval = @import("interval.zig").Interval;

test "visit all decls so their tests are found" {
    std.testing.refAllDecls(@This());
}

const std = @import("std");

test "visit all decls so their tests are found" {
    std.testing.refAllDecls(@This());
}

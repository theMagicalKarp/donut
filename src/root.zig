const std = @import("std");

pub const Interval = @import("interval.zig").Interval;
pub const Shading = @import("shading.zig").Shading;
pub const Scene = @import("scene.zig").Scene;
pub const Camera = @import("camera.zig").Camera;
pub const Geometry = @import("geometry/geometry.zig").Geometry;
pub const FrameSync = @import("frame_sync.zig").FrameSync;

test "visit all decls so their tests are found" {
    std.testing.refAllDecls(@This());
}

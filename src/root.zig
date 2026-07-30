const std = @import("std");

pub const Interval = @import("interval.zig").Interval;
pub const Shading = @import("shading.zig").Shading;
pub const Scene = @import("scene.zig").Scene;
pub const Camera = @import("camera.zig").Camera;
pub const Geometry = @import("geometry/geometry.zig").Geometry;
pub const FrameSync = @import("frame_sync.zig").FrameSync;

const config = @import("config.zig");

pub const Config = config.Config;
pub const Diagnostic = config.Diagnostic;
pub const SceneEntry = config.SceneEntry;
pub const Render = config.Render;
pub const CameraConfig = config.CameraConfig;
pub const Ui = config.Ui;

/// The configuration used when no file is given on the command line.
pub const default_config = @embedFile("default.jsonc");

test "visit all decls so their tests are found" {
    std.testing.refAllDecls(@This());
}

const std = @import("std");
const math = @import("zlm").as(f64);

const jsonc = @import("jsonc.zig");

const Geometry = @import("geometry/geometry.zig").Geometry;
const Interval = @import("interval.zig").Interval;
const Shading = @import("shading.zig").Shading;

const Allocator = std.mem.Allocator;

const Object = std.json.ObjectMap;
const Value = std.json.Value;

/// How deep a `"geometry"` chain may nest before we give up. Guards the stack
/// against a pathological (or hand-written-by-accident) config.
pub const max_depth = 64;

/// A config large enough to hit this is a mistake, not a scene.
pub const max_file_bytes = 1 << 20;

pub const Error = error{
    OutOfMemory,
    FileReadFailed,
    UnterminatedComment,
    JsonSyntax,
    NoScenes,
    NoChildren,
    MissingType,
    UnknownGeometryType,
    MissingField,
    UnknownField,
    TypeMismatch,
    ValueOutOfRange,
    InvalidRange,
    BadVector,
    BadMatrix,
    UnknownEnumValue,
    DepthExceeded,
};

/// Carries the human-readable reason a config was rejected. The library never
/// prints; `main` decides where the message goes.
pub const Diagnostic = struct {
    buffer: [512]u8 = undefined,
    len: usize = 0,

    pub fn message(self: *const Diagnostic) []const u8 {
        return self.buffer[0..self.len];
    }

    fn set(self: *Diagnostic, comptime fmt: []const u8, args: anytype) void {
        var writer = std.Io.Writer.fixed(&self.buffer);
        writer.print(fmt, args) catch {};
        self.len = writer.buffered().len;
    }
};

pub const Render = struct {
    target_fps: f64 = 30.0,
    max_steps: usize = 80,
    max_distance: f64 = 100.0,
    surface_distance: f64 = 0.01,
};

pub const CameraConfig = struct {
    look_at: math.Vec3,
    distance: Interval(f64),
    theta: Interval(f64),
    phi: Interval(f64),

    pub const default = CameraConfig{
        .look_at = math.Vec3.zero,
        .distance = .{ .current = 2.0, .default = 2.0, .min = 0.1, .max = 10.0, .step = 0.1 },
        .theta = .{
            .current = 0.0,
            .default = 0.0,
            .min = -std.math.floatMax(f64),
            .max = std.math.floatMax(f64),
            .step = 0.1,
        },
        .phi = .{ .current = 1.57, .default = 1.57, .min = 0.1, .max = 3.04, .step = 0.1 },
    };
};

pub const Ui = struct {
    accent: u8 = 5,
};

pub const SceneEntry = struct {
    name: []const u8,
    geometry: *const Geometry,
};

pub const Config = struct {
    const Self = @This();

    /// Owns every slice and `Geometry` node reachable from this struct.
    arena: std.heap.ArenaAllocator,

    render: Render,
    shading: Shading,
    camera: CameraConfig,
    ui: Ui,
    scenes: []const SceneEntry,

    pub fn fromSlice(gpa: Allocator, source: []const u8, diagnostic: ?*Diagnostic) Error!Self {
        // Comments are blanked in place, so stripping needs a buffer it may
        // write to; callers hand us `@embedFile` data and other read-only bytes.
        const scratch = try gpa.dupe(u8, source);
        defer gpa.free(scratch);

        var failure: jsonc.Failure = .{};
        jsonc.strip(scratch, &failure) catch |err| {
            if (diagnostic) |d| d.set("line {d}: unterminated block comment", .{failure.line});
            return err;
        };

        var scanner = std.json.Scanner.initCompleteInput(gpa, scratch);
        defer scanner.deinit();

        // The stripper preserved every offset, so these positions still name a
        // line and column in the file the user actually wrote.
        var diagnostics: std.json.Diagnostics = .{};
        scanner.enableDiagnostics(&diagnostics);

        var parsed = std.json.parseFromTokenSource(Value, gpa, &scanner, .{}) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            if (diagnostic) |d| d.set(
                "line {d}, column {d}: {s}",
                .{ diagnostics.getLine(), diagnostics.getColumn(), @errorName(err) },
            );
            return error.JsonSyntax;
        };
        defer parsed.deinit();

        // Safe to free `scratch` on the way out: `build` copies every string it
        // keeps into its own arena.
        return build(gpa, parsed.value, diagnostic);
    }

    pub fn fromFile(gpa: Allocator, io: std.Io, path: []const u8, diagnostic: ?*Diagnostic) Error!Self {
        const source = std.Io.Dir.cwd().readFileAlloc(
            io,
            path,
            gpa,
            .limited(max_file_bytes),
        ) catch |err| {
            if (err == error.OutOfMemory) {
                return error.OutOfMemory;
            }
            if (diagnostic) |d| {
                d.set("{s}", .{@errorName(err)});
            }
            return error.FileReadFailed;
        };
        defer gpa.free(source);

        return fromSlice(gpa, source, diagnostic);
    }

    pub fn deinit(self: *Self) void {
        self.arena.deinit();
    }
};

fn build(gpa: Allocator, root_value: Value, diagnostic: ?*Diagnostic) Error!Config {
    var ctx = ErrCtx.init(gpa, diagnostic);
    defer ctx.deinit();

    const root = switch (root_value) {
        .object => |object| object,
        else => return ctx.fail(error.TypeMismatch, "the top level must be a JSON object", .{}),
    };

    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();
    const alloc = arena.allocator();

    const render = try parseRender(root, &ctx);
    const shading = try parseShading(alloc, root, &ctx);
    const camera = try parseCamera(root, &ctx);
    const ui = try parseUi(root, &ctx);
    const scenes = try parseScenes(alloc, root, &ctx);

    return .{
        .arena = arena,
        .render = render,
        .shading = shading,
        .camera = camera,
        .ui = ui,
        .scenes = scenes,
    };
}

// -- error context ----------------------------------------------------------

/// Accumulates a breadcrumb trail (`scene[2].geometry.a`) so semantic failures —
/// the ones the JSON parser cannot know about — can say where they happened.
const ErrCtx = struct {
    const Self = @This();

    arena: std.heap.ArenaAllocator,
    path: std.ArrayList([]const u8),
    diagnostic: ?*Diagnostic,

    fn init(gpa: Allocator, diagnostic: ?*Diagnostic) Self {
        return .{
            .arena = std.heap.ArenaAllocator.init(gpa),
            .path = .empty,
            .diagnostic = diagnostic,
        };
    }

    fn deinit(self: *Self) void {
        self.path.deinit(self.arena.child_allocator);
        self.arena.deinit();
    }

    fn push(self: *Self, segment: []const u8) Error!void {
        try self.path.append(self.arena.child_allocator, segment);
    }

    /// For segments that need formatting, e.g. `scene[2]`.
    fn pushFmt(self: *Self, comptime fmt: []const u8, args: anytype) Error!void {
        const segment = try std.fmt.allocPrint(self.arena.allocator(), fmt, args);
        try self.push(segment);
    }

    fn pop(self: *Self) void {
        _ = self.path.pop();
    }

    fn fail(self: *Self, err: Error, comptime fmt: []const u8, args: anytype) Error {
        if (self.diagnostic) |d| {
            var writer = std.Io.Writer.fixed(&d.buffer);
            for (self.path.items, 0..) |segment, i| {
                if (i != 0) writer.writeByte('.') catch {};
                writer.writeAll(segment) catch {};
            }
            if (self.path.items.len != 0) writer.writeAll(": ") catch {};
            writer.print(fmt, args) catch {};
            d.len = writer.buffered().len;
        }
        return err;
    }
};

// -- value helpers ----------------------------------------------------------

fn asFloat(value: Value) ?f64 {
    return switch (value) {
        .float => |x| x,
        // `"rate": 0` should not be a type error just because it reads as an
        // integer.
        .integer => |x| @floatFromInt(x),
        // `.number_string` holds numbers outside i64/f64 range. Rejecting it
        // turns `1e400` into a type error rather than a silent infinity.
        else => null,
    };
}

fn wantFloat(ctx: *ErrCtx, key: []const u8, value: Value) Error!f64 {
    return asFloat(value) orelse ctx.fail(error.TypeMismatch, "'{s}' must be a number", .{key});
}

fn wantInt(comptime T: type, ctx: *ErrCtx, key: []const u8, value: Value) Error!T {
    const raw = switch (value) {
        .integer => |x| x,
        else => return ctx.fail(error.TypeMismatch, "'{s}' must be an integer", .{key}),
    };
    return std.math.cast(T, raw) orelse ctx.fail(
        error.ValueOutOfRange,
        "'{s}' = {d} is out of range for {s}",
        .{ key, raw, @typeName(T) },
    );
}

fn wantString(ctx: *ErrCtx, key: []const u8, value: Value) Error![]const u8 {
    return switch (value) {
        .string => |x| x,
        else => ctx.fail(error.TypeMismatch, "'{s}' must be a string", .{key}),
    };
}

/// Returned by value: an `ObjectMap` is a handle into the parse arena, so a copy
/// reads the same entries as the original.
fn wantObject(ctx: *ErrCtx, key: []const u8, value: Value) Error!Object {
    return switch (value) {
        .object => |x| x,
        else => ctx.fail(error.TypeMismatch, "'{s}' must be an object", .{key}),
    };
}

fn wantVec3(ctx: *ErrCtx, key: []const u8, value: Value) Error!math.Vec3 {
    const items = switch (value) {
        .array => |list| list.items,
        else => return ctx.fail(error.TypeMismatch, "'{s}' must be an array of 3 numbers", .{key}),
    };
    if (items.len != 3) return ctx.fail(
        error.BadVector,
        "'{s}' must have exactly 3 numbers, found {d}",
        .{ key, items.len },
    );

    var out: [3]f64 = undefined;
    for (items, 0..) |item, i| {
        out[i] = asFloat(item) orelse return ctx.fail(
            error.TypeMismatch,
            "'{s}[{d}]' must be a number",
            .{ key, i },
        );
    }
    return math.vec3(out[0], out[1], out[2]);
}

fn wantMat4(ctx: *ErrCtx, key: []const u8, value: Value) Error!math.Mat4 {
    const rows = switch (value) {
        .array => |list| list.items,
        else => return ctx.fail(error.TypeMismatch, "'{s}' must be an array of 4 rows", .{key}),
    };
    if (rows.len != 4) return ctx.fail(
        error.BadMatrix,
        "'{s}' must have exactly 4 rows, found {d}",
        .{ key, rows.len },
    );

    var out: [4][4]f64 = undefined;
    for (rows, 0..) |row, y| {
        const cells = switch (row) {
            .array => |list| list.items,
            else => return ctx.fail(error.BadMatrix, "'{s}[{d}]' must be an array", .{ key, y }),
        };
        if (cells.len != 4) return ctx.fail(
            error.BadMatrix,
            "'{s}[{d}]' must have exactly 4 numbers, found {d}",
            .{ key, y, cells.len },
        );
        for (cells, 0..) |cell, x| {
            out[y][x] = asFloat(cell) orelse return ctx.fail(
                error.TypeMismatch,
                "'{s}[{d}][{d}]' must be a number",
                .{ key, y, x },
            );
        }
    }
    return math.Mat4{ .fields = out };
}

fn wantEnum(comptime T: type, ctx: *ErrCtx, key: []const u8, value: Value) Error!T {
    const name = try wantString(ctx, key, value);
    return std.meta.stringToEnum(T, name) orelse ctx.fail(
        error.UnknownEnumValue,
        "'{s}' = \"{s}\" is not one of: {s}",
        .{ key, name, comptime enumNames(T) },
    );
}

fn enumNames(comptime T: type) []const u8 {
    comptime {
        var out: []const u8 = "";
        for (@typeInfo(T).@"enum".fields, 0..) |field, i| {
            if (i != 0) out = out ++ ", ";
            out = out ++ field.name;
        }
        return out;
    }
}

/// Rejects keys that no field of `T` claims, so a typo is an error rather than a
/// setting that silently does nothing. `allow_type` exempts the `type` tag that
/// selects a `Geometry` variant.
fn checkKeys(comptime T: type, object: Object, ctx: *ErrCtx, comptime allow_type: bool) Error!void {
    var it = object.iterator();
    next_key: while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        if (allow_type and std.mem.eql(u8, key, "type")) continue;
        inline for (@typeInfo(T).@"struct".fields) |field| {
            if (std.mem.eql(u8, key, field.name)) continue :next_key;
        }
        return ctx.fail(error.UnknownField, "unknown key '{s}'", .{key});
    }
}

// -- global sections --------------------------------------------------------

/// Every global section is optional, so a file holding nothing but a `"scene"`
/// array still renders with today's built-in values.
fn section(root: Object, name: []const u8, ctx: *ErrCtx) Error!?Object {
    const value = root.get(name) orelse return null;
    return try wantObject(ctx, name, value);
}

fn parseRender(root: Object, ctx: *ErrCtx) Error!Render {
    var out = Render{};
    const object = try section(root, "render", ctx) orelse return out;

    try ctx.push("render");
    defer ctx.pop();
    try checkKeys(Render, object, ctx, false);

    if (object.get("target_fps")) |v| out.target_fps = try wantFloat(ctx, "target_fps", v);
    if (object.get("max_steps")) |v| out.max_steps = try wantInt(usize, ctx, "max_steps", v);
    if (object.get("max_distance")) |v| out.max_distance = try wantFloat(ctx, "max_distance", v);
    if (object.get("surface_distance")) |v| out.surface_distance = try wantFloat(ctx, "surface_distance", v);

    // FrameSync divides by this, and a zero step would spin the render loop.
    if (!(out.target_fps > 0.0)) return ctx.fail(
        error.ValueOutOfRange,
        "'target_fps' must be greater than 0",
        .{},
    );
    return out;
}

fn parseShading(arena: Allocator, root: Object, ctx: *ErrCtx) Error!Shading {
    var out = Shading.new(math.vec3(1.0, -1.0, -1.0).normalize(), 2.4);
    const object = try section(root, "shading", ctx) orelse return out;

    try ctx.push("shading");
    defer ctx.pop();
    try checkKeys(Shading, object, ctx, false);

    if (object.get("gamma")) |v| out.gamma = try wantFloat(ctx, "gamma", v);
    if (object.get("light")) |v| out.light = (try wantVec3(ctx, "light", v)).normalize();
    if (object.get("lut")) |v| out.lut = try arena.dupe(u8, try wantString(ctx, "lut", v));

    if (out.lut.len == 0) return ctx.fail(error.ValueOutOfRange, "'lut' must not be empty", .{});
    if (out.gamma == 0.0) return ctx.fail(error.ValueOutOfRange, "'gamma' must not be 0", .{});
    return out;
}

fn parseCamera(root: Object, ctx: *ErrCtx) Error!CameraConfig {
    var out = CameraConfig.default;
    const object = try section(root, "camera", ctx) orelse return out;

    try ctx.push("camera");
    defer ctx.pop();
    try checkKeys(CameraConfig, object, ctx, false);

    if (object.get("look_at")) |v| out.look_at = try wantVec3(ctx, "look_at", v);
    out.distance = try parseInterval(object, "distance", out.distance, ctx);
    out.theta = try parseInterval(object, "theta", out.theta, ctx);
    out.phi = try parseInterval(object, "phi", out.phi, ctx);
    return out;
}

/// The subset of `Interval` a config may set; `current` is derived from `default`.
const IntervalKeys = struct {
    default: f64,
    min: f64,
    max: f64,
    step: f64,
};

fn parseInterval(
    parent: Object,
    key: []const u8,
    fallback: Interval(f64),
    ctx: *ErrCtx,
) Error!Interval(f64) {
    var out = fallback;
    const value = parent.get(key) orelse return out;
    const object = try wantObject(ctx, key, value);

    try ctx.push(key);
    defer ctx.pop();
    try checkKeys(IntervalKeys, object, ctx, false);

    if (object.get("default")) |v| out.default = try wantFloat(ctx, "default", v);
    if (object.get("min")) |v| out.min = try wantFloat(ctx, "min", v);
    if (object.get("max")) |v| out.max = try wantFloat(ctx, "max", v);
    if (object.get("step")) |v| out.step = try wantFloat(ctx, "step", v);

    if (out.min > out.max) return ctx.fail(
        error.InvalidRange,
        "'min' ({d}) must not exceed 'max' ({d})",
        .{ out.min, out.max },
    );
    if (out.default < out.min or out.default > out.max) return ctx.fail(
        error.InvalidRange,
        "'default' ({d}) must lie between 'min' ({d}) and 'max' ({d})",
        .{ out.default, out.min, out.max },
    );

    out.current = out.default;
    return out;
}

fn parseUi(root: Object, ctx: *ErrCtx) Error!Ui {
    var out = Ui{};
    const object = try section(root, "ui", ctx) orelse return out;

    try ctx.push("ui");
    defer ctx.pop();
    try checkKeys(Ui, object, ctx, false);

    if (object.get("accent")) |v| out.accent = try wantInt(u8, ctx, "accent", v);
    return out;
}

// -- scenes -----------------------------------------------------------------

fn parseScenes(arena: Allocator, root: Object, ctx: *ErrCtx) Error![]const SceneEntry {
    const value = root.get("scene") orelse return ctx.fail(
        error.NoScenes,
        "config defines no scenes; add at least one entry to \"scene\"",
        .{},
    );
    const entries = switch (value) {
        .array => |list| list.items,
        .object => return ctx.fail(
            error.TypeMismatch,
            "'scene' must be an array of objects, not a single object",
            .{},
        ),
        else => return ctx.fail(error.TypeMismatch, "'scene' must be an array of objects", .{}),
    };
    if (entries.len == 0) return ctx.fail(
        error.NoScenes,
        "config defines no scenes; add at least one entry to \"scene\"",
        .{},
    );

    const out = try arena.alloc(SceneEntry, entries.len);
    for (entries, 0..) |entry, i| {
        try ctx.pushFmt("scene[{d}]", .{i});
        defer ctx.pop();

        const object = try wantObject(ctx, "scene", entry);
        try checkKeys(SceneEntry, object, ctx, false);

        const name = object.get("name") orelse return ctx.fail(error.MissingField, "missing 'name'", .{});
        const geometry = object.get("geometry") orelse return ctx.fail(
            error.MissingField,
            "missing 'geometry'",
            .{},
        );

        try ctx.push("geometry");
        defer ctx.pop();

        out[i] = .{
            .name = try arena.dupe(u8, try wantString(ctx, "name", name)),
            .geometry = try parseGeometry(arena, try wantObject(ctx, "geometry", geometry), ctx, 0),
        };
    }
    return out;
}

/// Builds a `Geometry` node by reflecting over the union: `type` picks the
/// variant, and every other key is the payload struct's field name verbatim.
/// Adding a variant to `Geometry` makes it configurable with no change here.
fn parseGeometry(
    arena: Allocator,
    object: Object,
    ctx: *ErrCtx,
    depth: usize,
) Error!*const Geometry {
    if (depth >= max_depth) return ctx.fail(
        error.DepthExceeded,
        "geometry nests deeper than {d} levels",
        .{max_depth},
    );

    const tag_value = object.get("type") orelse return ctx.fail(error.MissingType, "missing 'type'", .{});
    const tag = try wantString(ctx, "type", tag_value);

    inline for (@typeInfo(Geometry).@"union".fields) |variant| {
        if (std.mem.eql(u8, variant.name, tag)) {
            try checkKeys(variant.type, object, ctx, true);

            var payload: variant.type = undefined;
            inline for (@typeInfo(variant.type).@"struct".fields) |field| {
                @field(payload, field.name) = try parseField(
                    field.type,
                    arena,
                    object,
                    field.name,
                    ctx,
                    depth,
                );
            }

            const node = try arena.create(Geometry);
            node.* = @unionInit(Geometry, variant.name, payload);
            return node;
        }
    }
    return ctx.fail(error.UnknownGeometryType, "unknown geometry type \"{s}\"", .{tag});
}

const FieldKind = enum { number, integer, vec3, mat4, child, children, enumeration };

/// Comptime-only classifier. A `Geometry` variant carrying a field type this
/// cannot place fails the build rather than surprising a user at runtime.
fn fieldKind(comptime T: type) FieldKind {
    if (T == math.Vec3) return .vec3;
    if (T == math.Mat4) return .mat4;
    if (T == *const Geometry) return .child;
    if (T == []const *const Geometry) return .children;
    return switch (@typeInfo(T)) {
        .float => .number,
        .int => .integer,
        .@"enum" => .enumeration,
        else => @compileError("config: no JSONC representation for geometry field type " ++ @typeName(T)),
    };
}

fn parseField(
    comptime T: type,
    arena: Allocator,
    object: Object,
    comptime name: []const u8,
    ctx: *ErrCtx,
    depth: usize,
) Error!T {
    const value = object.get(name) orelse return ctx.fail(error.MissingField, "missing '{s}'", .{name});

    switch (comptime fieldKind(T)) {
        .number => return @floatCast(try wantFloat(ctx, name, value)),
        .integer => return try wantInt(T, ctx, name, value),
        .vec3 => return try wantVec3(ctx, name, value),
        .mat4 => return try wantMat4(ctx, name, value),
        .enumeration => return try wantEnum(T, ctx, name, value),
        .child => {
            const child = try wantObject(ctx, name, value);
            try ctx.push(name);
            defer ctx.pop();
            return try parseGeometry(arena, child, ctx, depth + 1);
        },
        .children => {
            const items = switch (value) {
                .array => |list| list.items,
                else => return ctx.fail(
                    error.TypeMismatch,
                    "'{s}' must be an array of geometry objects",
                    .{name},
                ),
            };
            // An empty combinator renders nothing at all, which is never what
            // anyone meant to write.
            if (items.len == 0) return ctx.fail(
                error.NoChildren,
                "'{s}' must have at least one child",
                .{name},
            );

            const out = try arena.alloc(*const Geometry, items.len);
            for (items, 0..) |item, i| {
                try ctx.pushFmt("{s}[{d}]", .{ name, i });
                defer ctx.pop();
                out[i] = try parseGeometry(
                    arena,
                    try wantObject(ctx, name, item),
                    ctx,
                    depth + 1,
                );
            }
            return out;
        },
    }
}

// -- tests ------------------------------------------------------------------

const testing = std.testing;

fn expectFails(source: []const u8, expected: Error) !void {
    var diagnostic = Diagnostic{};
    const result = Config.fromSlice(testing.allocator, source, &diagnostic);
    try testing.expectError(expected, result);
    // A rejection the user cannot act on is not much better than a crash.
    try testing.expect(diagnostic.message().len > 0);
}

test "every Geometry variant is constructible from JSONC" {
    inline for (@typeInfo(Geometry).@"union".fields) |variant| {
        inline for (@typeInfo(variant.type).@"struct".fields) |field| {
            _ = comptime fieldKind(field.type);
        }
    }
}

test "the embedded default config parses into the four built-in scenes" {
    var diagnostic = Diagnostic{};
    var config = Config.fromSlice(
        testing.allocator,
        @embedFile("default.jsonc"),
        &diagnostic,
    ) catch |err| {
        std.debug.print("default.jsonc: {s}: {s}\n", .{ @errorName(err), diagnostic.message() });
        return err;
    };
    defer config.deinit();

    try testing.expectEqual(@as(usize, 4), config.scenes.len);
    try testing.expectEqualStrings("Donut", config.scenes[0].name);
    try testing.expectEqualStrings("Morph", config.scenes[1].name);
    try testing.expectEqualStrings("The Spinz", config.scenes[2].name);
    try testing.expectEqualStrings("Marching Octahedrons", config.scenes[3].name);
}

test "the embedded default reproduces the donut tree shape" {
    var config = try Config.fromSlice(testing.allocator, @embedFile("default.jsonc"), null);
    defer config.deinit();

    const spinx = config.scenes[0].geometry.spinx;
    try testing.expectEqual(@as(f64, 0.001), spinx.rate);

    const spinz = spinx.geometry.spinz;
    try testing.expectEqual(@as(f64, 0.002), spinz.rate);

    const translate = spinz.geometry.translate;
    try testing.expectEqual(math.vec3(0.0, 0.05, 0.0), translate.direction);

    const torus = translate.geometry.torus;
    try testing.expectEqual(@as(f64, 0.45), torus.inner);
    try testing.expectEqual(@as(f64, 1.0), torus.outer);
}

test "the embedded default keeps today's global settings" {
    var config = try Config.fromSlice(testing.allocator, @embedFile("default.jsonc"), null);
    defer config.deinit();

    try testing.expectEqual(@as(f64, 30.0), config.render.target_fps);
    try testing.expectEqual(@as(usize, 80), config.render.max_steps);
    try testing.expectEqual(@as(f64, 100.0), config.render.max_distance);
    try testing.expectEqual(@as(f64, 0.01), config.render.surface_distance);

    try testing.expectEqual(@as(f64, 2.4), config.shading.gamma);
    try testing.expectEqualStrings(".,-~:;=!*#$@", config.shading.lut);
    try testing.expectEqual(math.vec3(1.0, -1.0, -1.0).normalize(), config.shading.light);

    try testing.expectEqual(@as(u8, 5), config.ui.accent);
    try testing.expectEqual(math.Vec3.zero, config.camera.look_at);
    try testing.expectEqual(@as(f64, 2.0), config.camera.distance.current);
    try testing.expectEqual(@as(f64, 1.57), config.camera.phi.current);
}

test "omitting every global section falls back to the built-in values" {
    var config = try Config.fromSlice(testing.allocator,
        \\{
        \\  "scene": [
        \\    { "name": "Only", "geometry": { "type": "sphere", "radius": 1.0 } }
        \\  ]
        \\}
    , null);
    defer config.deinit();

    try testing.expectEqual(Render{}, config.render);
    try testing.expectEqual(Ui{}, config.ui);
    try testing.expectEqual(@as(f64, 2.4), config.shading.gamma);
    try testing.expectEqualStrings(".,-~:;=!*#$@", config.shading.lut);
    try testing.expectEqual(CameraConfig.default.phi, config.camera.phi);
    try testing.expectEqual(CameraConfig.default.theta, config.camera.theta);
    try testing.expectEqual(@as(f64, 1.0), config.scenes[0].geometry.sphere.radius);
}

test "comments are ignored wherever they appear" {
    var diagnostic = Diagnostic{};
    var config = Config.fromSlice(testing.allocator,
        \\// A leading comment, before the document even opens.
        \\{
        \\  "render": {
        \\    "target_fps": 60.0 // trailing, right after the value
        \\  },
        \\  /* A block comment
        \\     spanning several lines. */
        \\  "scene": [
        \\    {
        \\      "name": "Commented", // and one here
        \\      "geometry": { "type": "sphere", "radius": 1.0 }
        \\    }
        \\  ]
        \\}
        \\// And a trailing one.
    , &diagnostic) catch |err| {
        std.debug.print("{s}: {s}\n", .{ @errorName(err), diagnostic.message() });
        return err;
    };
    defer config.deinit();

    try testing.expectEqual(@as(f64, 60.0), config.render.target_fps);
    try testing.expectEqualStrings("Commented", config.scenes[0].name);
}

test "a comment-looking string is data, not a comment" {
    var config = try Config.fromSlice(testing.allocator,
        \\{
        \\  "shading": { "lut": "//*ramp*//" },
        \\  "scene": [
        \\    { "name": "Slashes", "geometry": { "type": "sphere", "radius": 1.0 } }
        \\  ]
        \\}
    , null);
    defer config.deinit();

    try testing.expectEqualStrings("//*ramp*//", config.shading.lut);
}

test "a float field accepts an integer literal" {
    var config = try Config.fromSlice(testing.allocator,
        \\{
        \\  "scene": [
        \\    {
        \\      "name": "Integers",
        \\      "geometry": {
        \\        "type": "spinx", "rate": 0,
        \\        "geometry": { "type": "sphere", "radius": 2 }
        \\      }
        \\    }
        \\  ]
        \\}
    , null);
    defer config.deinit();

    try testing.expectEqual(@as(f64, 0.0), config.scenes[0].geometry.spinx.rate);
    try testing.expectEqual(@as(f64, 2.0), config.scenes[0].geometry.spinx.geometry.sphere.radius);
}

test "enum fields map from strings" {
    var config = try Config.fromSlice(testing.allocator,
        \\{
        \\  "scene": [
        \\    {
        \\      "name": "Lerp",
        \\      "geometry": {
        \\        "type": "lerp",
        \\        "start": [0, 0, 3],
        \\        "stop": [0, 0, -3],
        \\        "time_scale": 4000.0,
        \\        "ease": "smoother",
        \\        "mode": "ping_pong",
        \\        "geometry": { "type": "sphere", "radius": 0.25 }
        \\      }
        \\    }
        \\  ]
        \\}
    , null);
    defer config.deinit();

    const lerp = config.scenes[0].geometry.lerp;
    try testing.expectEqual(.smoother, lerp.ease);
    try testing.expectEqual(.ping_pong, lerp.mode);
    try testing.expectEqual(math.vec3(0.0, 0.0, 3.0), lerp.start);
    try testing.expectEqual(math.vec3(0.0, 0.0, -3.0), lerp.stop);
}

test "a Mat4 field reads as four rows of four" {
    var config = try Config.fromSlice(testing.allocator,
        \\{
        \\  "scene": [
        \\    {
        \\      "name": "Transform",
        \\      "geometry": {
        \\        "type": "transform",
        \\        "geometry": { "type": "sphere", "radius": 1.0 },
        \\        "matrix": [
        \\          [1, 0, 0, 0],
        \\          [0, 1, 0, 0],
        \\          [0, 0, 1, 0],
        \\          [0, 0, 0, 1]
        \\        ]
        \\      }
        \\    }
        \\  ]
        \\}
    , null);
    defer config.deinit();

    try testing.expectEqual(math.Mat4.identity, config.scenes[0].geometry.transform.matrix);
}

test "the variants no built-in scene uses are still reachable" {
    var diagnostic = Diagnostic{};
    var config = Config.fromSlice(testing.allocator,
        \\{
        \\  "scene": [
        \\    {
        \\      "name": "Leftovers",
        \\      "geometry": {
        \\        "type": "subtraction",
        \\        "geometry": [
        \\          { "type": "box_frame", "dimensions": [1, 1, 1], "thickness": 0.1 },
        \\          {
        \\            "type": "intersection",
        \\            "geometry": [
        \\              {
        \\                "type": "scale", "amount": 2.0,
        \\                "geometry": { "type": "octahedron", "size": 0.5 }
        \\              },
        \\              {
        \\                "type": "repeat", "spacing": 1.0,
        \\                "geometry": {
        \\                  "type": "rotatey", "angle": 0.5,
        \\                  "geometry": {
        \\                    "type": "rotatez", "angle": 0.25,
        \\                    "geometry": { "type": "box", "dimensions": [1, 2, 3] }
        \\                  }
        \\                }
        \\              }
        \\            ]
        \\          }
        \\        ]
        \\      }
        \\    }
        \\  ]
        \\}
    , &diagnostic) catch |err| {
        std.debug.print("{s}: {s}\n", .{ @errorName(err), diagnostic.message() });
        return err;
    };
    defer config.deinit();

    const subtraction = config.scenes[0].geometry.subtraction.geometry;
    try testing.expectEqual(@as(usize, 2), subtraction.len);
    try testing.expectEqual(@as(f64, 0.1), subtraction[0].box_frame.thickness);

    const intersection = subtraction[1].intersection.geometry;
    try testing.expectEqual(@as(f64, 2.0), intersection[0].scale.amount);
    try testing.expectEqual(@as(f64, 0.5), intersection[1].repeat.geometry.rotatey.angle);
    try testing.expectEqual(
        @as(f64, 0.25),
        intersection[1].repeat.geometry.rotatey.geometry.rotatez.angle,
    );
}

test "a combinator takes any number of children" {
    var diagnostic = Diagnostic{};
    var config = Config.fromSlice(testing.allocator,
        \\{
        \\  "scene": [
        \\    {
        \\      "name": "Five",
        \\      "geometry": {
        \\        "type": "union_exact",
        \\        "geometry": [
        \\          { "type": "sphere", "radius": 1.0 },
        \\          { "type": "sphere", "radius": 2.0 },
        \\          { "type": "sphere", "radius": 3.0 },
        \\          { "type": "sphere", "radius": 4.0 },
        \\          { "type": "sphere", "radius": 5.0 }
        \\        ]
        \\      }
        \\    }
        \\  ]
        \\}
    , &diagnostic) catch |err| {
        std.debug.print("{s}: {s}\n", .{ @errorName(err), diagnostic.message() });
        return err;
    };
    defer config.deinit();

    const children = config.scenes[0].geometry.union_exact.geometry;
    try testing.expectEqual(@as(usize, 5), children.len);
    try testing.expectEqual(@as(f64, 1.0), children[0].sphere.radius);
    try testing.expectEqual(@as(f64, 5.0), children[4].sphere.radius);

    // 10 units out, the nearest surface is the largest sphere's.
    const point = math.vec3(10.0, 0.0, 0.0);
    try testing.expectEqual(@as(f64, 5.0), config.scenes[0].geometry.distance(0.0, point));
}

test "a single child is legal and behaves as that child" {
    var config = try Config.fromSlice(testing.allocator,
        \\{
        \\  "scene": [
        \\    {
        \\      "name": "One",
        \\      "geometry": {
        \\        "type": "union_exact",
        \\        "geometry": [ { "type": "sphere", "radius": 2.0 } ]
        \\      }
        \\    }
        \\  ]
        \\}
    , null);
    defer config.deinit();

    const point = math.vec3(5.0, 0.0, 0.0);
    try testing.expectEqual(@as(f64, 3.0), config.scenes[0].geometry.distance(0.0, point));
}

test "subtraction carves every later child out of the first" {
    var config = try Config.fromSlice(testing.allocator,
        \\{
        \\  "scene": [
        \\    {
        \\      "name": "Shell",
        \\      "geometry": {
        \\        "type": "subtraction",
        \\        "geometry": [
        \\          { "type": "sphere", "radius": 2.0 },
        \\          { "type": "sphere", "radius": 1.0 }
        \\        ]
        \\      }
        \\    },
        \\    {
        \\      "name": "Reversed",
        \\      "geometry": {
        \\        "type": "subtraction",
        \\        "geometry": [
        \\          { "type": "sphere", "radius": 1.0 },
        \\          { "type": "sphere", "radius": 2.0 }
        \\        ]
        \\      }
        \\    }
        \\  ]
        \\}
    , null);
    defer config.deinit();

    const shell = config.scenes[0].geometry;
    const reversed = config.scenes[1].geometry;

    // Between the two radii: solid in the shell, hollowed out when reversed.
    const between = math.vec3(1.5, 0.0, 0.0);
    try testing.expectEqual(@as(f64, -0.5), shell.distance(0.0, between));
    try testing.expectEqual(@as(f64, 0.5), reversed.distance(0.0, between));

    // Dead centre is inside the carved-away core either way.
    const centre = math.Vec3.zero;
    try testing.expectEqual(@as(f64, 1.0), shell.distance(0.0, centre));
    try testing.expectEqual(@as(f64, 2.0), reversed.distance(0.0, centre));
}

test "the embedded default unions The Spinz in a single node" {
    var config = try Config.fromSlice(testing.allocator, @embedFile("default.jsonc"), null);
    defer config.deinit();

    // Three orbiting spheres plus the tumbling box, flat. As nested binary
    // unions this took three `union_exact` nodes.
    const children = config.scenes[2].geometry.union_exact.geometry;
    try testing.expectEqual(@as(usize, 4), children.len);
    try testing.expectEqual(@as(f64, 0.25), children[0].rotatex.angle);
    try testing.expectEqual(@as(f64, 1000.0), children[1].time_offset.duration);
    try testing.expectEqual(@as(f64, 1500.0), children[2].time_offset.duration);
    try testing.expectEqual(@as(f64, 0.001), children[3].spinx.rate);

    // Morph blends exactly two, in list order.
    const morph = config.scenes[1].geometry.union_smooth;
    try testing.expectEqual(@as(f64, 2.0), morph.smooth);
    try testing.expectEqual(@as(usize, 2), morph.geometry.len);
    try testing.expectEqual(@as(f64, 4000.0), morph.geometry[0].lerp.time_scale);
}

test "a child list nests as deep as a single child" {
    var diagnostic = Diagnostic{};
    const result = Config.fromSlice(testing.allocator,
        \\{
        \\  "scene": [
        \\    {
        \\      "name": "Deep list",
        \\      "geometry": {
        \\        "type": "union_exact",
        \\        "geometry": [
        \\          { "type": "sphere", "radius": 1.0 },
        \\          { "type": "union_exact", "geometry": [ { "type": "torrus" } ] }
        \\        ]
        \\      }
        \\    }
        \\  ]
        \\}
    , &diagnostic);

    try testing.expectError(error.UnknownGeometryType, result);
    try testing.expectEqualStrings(
        "scene[0].geometry.geometry[1].geometry[0]: unknown geometry type \"torrus\"",
        diagnostic.message(),
    );
}

test "an unknown geometry type names the offending path" {
    var diagnostic = Diagnostic{};
    const result = Config.fromSlice(testing.allocator,
        \\{
        \\  "scene": [
        \\    {
        \\      "name": "Typo",
        \\      "geometry": {
        \\        "type": "union_exact",
        \\        "geometry": [
        \\          { "type": "sphere", "radius": 1.0 },
        \\          { "type": "torrus", "inner": 0.5, "outer": 1.0 }
        \\        ]
        \\      }
        \\    }
        \\  ]
        \\}
    , &diagnostic);

    try testing.expectError(error.UnknownGeometryType, result);
    try testing.expectEqualStrings(
        "scene[0].geometry.geometry[1]: unknown geometry type \"torrus\"",
        diagnostic.message(),
    );
}

test "a syntax error reports the line and column of the original file" {
    var diagnostic = Diagnostic{};
    const result = Config.fromSlice(testing.allocator,
        \\{
        \\  // Blanking rather than deleting this comment is what keeps the
        \\  // reported line honest.
        \\  "scene": [ }
        \\}
    , &diagnostic);

    try testing.expectError(error.JsonSyntax, result);
    try testing.expect(std.mem.startsWith(u8, diagnostic.message(), "line 4, column"));
}

test "an unterminated block comment names the line it opened on" {
    var diagnostic = Diagnostic{};
    const result = Config.fromSlice(testing.allocator,
        \\{
        \\  "scene": []
        \\  /* opened here and never closed
        \\}
    , &diagnostic);

    try testing.expectError(error.UnterminatedComment, result);
    try testing.expectEqualStrings("line 3: unterminated block comment", diagnostic.message());
}

test "rejected configs" {
    try expectFails(
        \\{ "scene": [ { "name": "No geometry key" } ] }
    , error.MissingField);

    try expectFails(
        \\{ "scene": [ { "geometry": { "type": "sphere", "radius": 1.0 } } ] }
    , error.MissingField);

    try expectFails(
        \\{ "scene": [ { "name": "Missing payload field",
        \\  "geometry": { "type": "torus", "inner": 0.45 } } ] }
    , error.MissingField);

    try expectFails(
        \\{ "scene": [ { "name": "No type", "geometry": { "radius": 1.0 } } ] }
    , error.MissingType);

    try expectFails(
        \\{ "scene": [ { "name": "Child is not an object",
        \\  "geometry": { "type": "spinx", "rate": 0.1, "geometry": 3 } } ] }
    , error.TypeMismatch);

    try expectFails(
        \\{ "scene": [ { "name": "Short vector",
        \\  "geometry": { "type": "box", "dimensions": [1, 2] } } ] }
    , error.BadVector);

    try expectFails(
        \\{ "scene": [ { "name": "Empty combinator",
        \\  "geometry": { "type": "union_exact", "geometry": [] } } ] }
    , error.NoChildren);

    try expectFails(
        \\{ "scene": [ { "name": "Combinator given one child, not a list",
        \\  "geometry": { "type": "union_exact",
        \\    "geometry": { "type": "sphere", "radius": 1.0 } } } ] }
    , error.TypeMismatch);

    try expectFails(
        \\{ "scene": [ { "name": "Child list holding a number",
        \\  "geometry": { "type": "union_exact",
        \\    "geometry": [ { "type": "sphere", "radius": 1.0 }, 3 ] } } ] }
    , error.TypeMismatch);

    try expectFails(
        \\{ "scene": [ { "name": "Combinator still spelled a/b",
        \\  "geometry": { "type": "union_exact",
        \\    "a": { "type": "sphere", "radius": 1.0 },
        \\    "b": { "type": "sphere", "radius": 2.0 } } } ] }
    , error.UnknownField);

    try expectFails(
        \\{ "scene": [ { "name": "Typo'd payload key",
        \\  "geometry": { "type": "sphere", "radius": 1.0, "radiuss": 2.0 } } ] }
    , error.UnknownField);

    try expectFails(
        \\{ "scene": [ { "name": "Bad enum", "geometry": {
        \\  "type": "lerp", "start": [0, 0, 0], "stop": [0, 0, 1], "time_scale": 1.0,
        \\  "ease": "bouncy", "mode": "loop",
        \\  "geometry": { "type": "sphere", "radius": 1.0 } } } ] }
    , error.UnknownEnumValue);

    try expectFails(
        \\{ "render": { "target_fps": 30.0 } }
    , error.NoScenes);
    try expectFails(
        \\{ "scene": [] }
    , error.NoScenes);
    try expectFails(
        \\{ "scene": { "name": "A single object" } }
    , error.TypeMismatch);
    try expectFails(
        \\[ { "name": "Top level array" } ]
    , error.TypeMismatch);

    try expectFails(
        \\{
        \\  "render": { "target_fps": 0.0 },
        \\  "scene": [ { "name": "Zero FPS",
        \\    "geometry": { "type": "sphere", "radius": 1.0 } } ]
        \\}
    , error.ValueOutOfRange);

    try expectFails(
        \\{
        \\  "shading": { "lut": "" },
        \\  "scene": [ { "name": "Empty ramp",
        \\    "geometry": { "type": "sphere", "radius": 1.0 } } ]
        \\}
    , error.ValueOutOfRange);

    try expectFails(
        \\{
        \\  "camera": { "distance": { "default": 50.0, "min": 0.1, "max": 10.0 } },
        \\  "scene": [ { "name": "Default outside range",
        \\    "geometry": { "type": "sphere", "radius": 1.0 } } ]
        \\}
    , error.InvalidRange);

    try expectFails(
        \\{
        \\  "ui": { "accent": 500 },
        \\  "scene": [ { "name": "Accent overflows u8",
        \\    "geometry": { "type": "sphere", "radius": 1.0 } } ]
        \\}
    , error.ValueOutOfRange);

    try expectFails(
        \\{
        \\  "render": { "targt_fps": 30.0 },
        \\  "scene": [ { "name": "Typo'd global",
        \\    "geometry": { "type": "sphere", "radius": 1.0 } } ]
        \\}
    , error.UnknownField);

    try expectFails("this is not json\n", error.JsonSyntax);

    // std.json rejects duplicates outright, matching what TOML used to do.
    try expectFails(
        \\{
        \\  "ui": { "accent": 1 },
        \\  "ui": { "accent": 2 },
        \\  "scene": [ { "name": "Twice",
        \\    "geometry": { "type": "sphere", "radius": 1.0 } } ]
        \\}
    , error.JsonSyntax);

    // Trailing commas are JSON5, not JSONC as we accept it.
    try expectFails(
        \\{
        \\  "scene": [ { "name": "Trailing comma",
        \\    "geometry": { "type": "sphere", "radius": 1.0 } }, ]
        \\}
    , error.JsonSyntax);
}

test "nesting past the depth cap is rejected rather than smashing the stack" {
    var source: std.Io.Writer.Allocating = .init(testing.allocator);
    defer source.deinit();

    try source.writer.writeAll("{\"scene\": [{\"name\": \"Deep\", \"geometry\": ");
    for (0..max_depth + 1) |_| {
        try source.writer.writeAll("{\"type\": \"spinx\", \"rate\": 0.0, \"geometry\": ");
    }
    try source.writer.writeAll("{\"type\": \"sphere\", \"radius\": 1.0}");
    for (0..max_depth + 1) |_| {
        try source.writer.writeAll("}");
    }
    try source.writer.writeAll("}]}\n");

    try expectFails(source.written(), error.DepthExceeded);
}

test "a config file is read from disk" {
    const io = testing.io;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(io, .{
        .sub_path = "scratch.jsonc",
        .data =
        \\{
        \\  // Read from a real file, comments and all.
        \\  "scene": [
        \\    { "name": "From disk", "geometry": { "type": "sphere", "radius": 3.0 } }
        \\  ]
        \\}
        ,
    });

    // `tmpDir` roots itself at `.zig-cache/tmp` under the cwd, which is also
    // what `fromFile` resolves against.
    const path = try std.fmt.allocPrint(
        testing.allocator,
        ".zig-cache/tmp/{s}/scratch.jsonc",
        .{tmp.sub_path},
    );
    defer testing.allocator.free(path);

    var config = try Config.fromFile(testing.allocator, io, path, null);
    defer config.deinit();

    try testing.expectEqualStrings("From disk", config.scenes[0].name);
    try testing.expectEqual(@as(f64, 3.0), config.scenes[0].geometry.sphere.radius);
}

test "a missing file reports why it could not be read" {
    var diagnostic = Diagnostic{};
    const result = Config.fromFile(
        testing.allocator,
        testing.io,
        "/definitely/not/here.jsonc",
        &diagnostic,
    );

    try testing.expectError(error.FileReadFailed, result);
    try testing.expectEqualStrings("FileNotFound", diagnostic.message());
}

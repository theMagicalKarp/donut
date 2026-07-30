const std = @import("std");

pub const Error = error{UnterminatedComment};

/// Where stripping gave up, so the caller can say more than "bad file".
pub const Failure = struct {
    /// 1-based line holding the `/*` that was never closed.
    line: usize = 0,
};

/// Overwrites every comment in `buffer` with spaces, in place, leaving the
/// length and every newline untouched.
pub fn strip(buffer: []u8, failure: ?*Failure) Error!void {
    var line: usize = 1;
    var i: usize = 0;

    while (i < buffer.len) {
        switch (buffer[i]) {
            '\n' => {
                line += 1;
                i += 1;
            },
            // A `//` inside a string is data — think of a `lut` full of
            // slashes — so strings are skipped whole.
            '"' => i = skipString(buffer, i, &line),
            '/' => {
                if (i + 1 == buffer.len) break;
                switch (buffer[i + 1]) {
                    '/' => {
                        while (i < buffer.len and buffer[i] != '\n') : (i += 1) buffer[i] = ' ';
                    },
                    '*' => {
                        const opened_at = line;
                        i = blankBlock(buffer, i, &line) orelse {
                            if (failure) |f| f.line = opened_at;
                            return error.UnterminatedComment;
                        };
                    },
                    // A stray `/` is not ours to judge; std.json will reject it.
                    else => i += 1,
                }
            },
            else => i += 1,
        }
    }
}

/// Returns the index just past the closing quote, or the end of the buffer when
/// the string is never closed — an unterminated string is `std.json`'s error to
/// report, not ours.
fn skipString(buffer: []const u8, start: usize, line: *usize) usize {
    var i = start + 1;
    while (i < buffer.len) : (i += 1) {
        switch (buffer[i]) {
            // Whatever follows is escaped, including a quote.
            '\\' => i += 1,
            '"' => return i + 1,
            // Illegal inside a JSON string, but counting it keeps the line
            // number honest for the error std.json is about to raise.
            '\n' => line.* += 1,
            else => {},
        }
    }
    return buffer.len;
}

/// Blanks `/* ... */` beginning at `start`, returning the index just past the
/// closing delimiter, or null when there is not one.
fn blankBlock(buffer: []u8, start: usize, line: *usize) ?usize {
    // The opening pair is blanked up front so that `/*/` cannot read as a
    // complete comment: the search for `*/` starts after it.
    buffer[start] = ' ';
    buffer[start + 1] = ' ';

    var i = start + 2;
    while (i < buffer.len) : (i += 1) {
        if (buffer[i] == '\n') {
            // Kept, or every line after this comment would shift.
            line.* += 1;
            continue;
        }
        const closing = buffer[i] == '*' and i + 1 < buffer.len and buffer[i + 1] == '/';
        buffer[i] = ' ';
        if (closing) {
            buffer[i + 1] = ' ';
            return i + 2;
        }
    }
    return null;
}

// -- tests ------------------------------------------------------------------

const testing = std.testing;

/// Strips a copy of `source` and checks it against `expected`, which must line
/// up byte for byte.
fn expectStripped(source: []const u8, expected: []const u8) !void {
    const buffer = try testing.allocator.dupe(u8, source);
    defer testing.allocator.free(buffer);

    try strip(buffer, null);
    try testing.expectEqualStrings(expected, buffer);
}

test "a line comment becomes spaces and keeps its newline" {
    try expectStripped(
        "{\"a\": 1} // trailing\n{\"b\": 2}\n",
        "{\"a\": 1}            \n{\"b\": 2}\n",
    );
}

test "a line comment at end of input needs no newline" {
    try expectStripped("1 // done", "1        ");
}

test "a block comment on one line becomes spaces" {
    try expectStripped("[1, /* two */ 3]", "[1,           3]");
}

test "a block comment spanning lines keeps every newline" {
    try expectStripped(
        "{\n/* one\n   two */\n}",
        "{\n      \n         \n}",
    );
}

test "a comment cannot start inside a string" {
    try expectStripped(
        "{\"lut\": \"//not a comment\", \"b\": \"/* nor this */\"}",
        "{\"lut\": \"//not a comment\", \"b\": \"/* nor this */\"}",
    );
}

test "an escaped quote does not end a string" {
    try expectStripped(
        "{\"a\": \"say \\\" // still in\"} // out",
        "{\"a\": \"say \\\" // still in\"}       ",
    );
}

test "a lone slash is left for std.json to reject" {
    try expectStripped("{\"a\": / 1}", "{\"a\": / 1}");
}

test "`/*/` does not close itself" {
    var failure: Failure = .{};
    const buffer = try testing.allocator.dupe(u8, "[1] /*/");
    defer testing.allocator.free(buffer);

    try testing.expectError(error.UnterminatedComment, strip(buffer, &failure));
}

test "an unterminated block comment names the line it opened on" {
    var failure: Failure = .{};
    const buffer = try testing.allocator.dupe(u8, "{\n\"a\": 1\n} /* never closed\nand on\n");
    defer testing.allocator.free(buffer);

    try testing.expectError(error.UnterminatedComment, strip(buffer, &failure));
    try testing.expectEqual(@as(usize, 3), failure.line);
}

test "stripping never changes the length" {
    const sources = [_][]const u8{
        "// only a comment",
        "{} /* a */ // b",
        "{\"a\": \"//\"} /* c\nd */",
        "",
        "/",
    };
    for (sources) |source| {
        const buffer = try testing.allocator.dupe(u8, source);
        defer testing.allocator.free(buffer);

        strip(buffer, null) catch {};
        try testing.expectEqual(source.len, buffer.len);
    }
}

test "a stripped document still parses, and comments leave no trace" {
    const source =
        \\{
        \\  // the ramp, dark to bright
        \\  "lut": ".,-~:;=!*#$@",
        \\  /* a block
        \\     comment */
        \\  "accent": 5
        \\}
    ;
    const buffer = try testing.allocator.dupe(u8, source);
    defer testing.allocator.free(buffer);
    try strip(buffer, null);

    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, buffer, .{});
    defer parsed.deinit();

    try testing.expectEqual(@as(usize, 2), parsed.value.object.count());
    try testing.expectEqualStrings(".,-~:;=!*#$@", parsed.value.object.get("lut").?.string);
    try testing.expectEqual(@as(i64, 5), parsed.value.object.get("accent").?.integer);
}

test "a syntax error after a comment still reports the original line" {
    // The point of blanking instead of deleting: line 4 is line 4 either way.
    const source =
        \\{
        \\  // a comment that would shift things if it were deleted
        \\  "a": 1,
        \\  "b": }
        \\}
    ;
    const buffer = try testing.allocator.dupe(u8, source);
    defer testing.allocator.free(buffer);
    try strip(buffer, null);

    var scanner = std.json.Scanner.initCompleteInput(testing.allocator, buffer);
    defer scanner.deinit();

    var diagnostics: std.json.Diagnostics = .{};
    scanner.enableDiagnostics(&diagnostics);

    try testing.expectError(
        error.SyntaxError,
        std.json.parseFromTokenSource(std.json.Value, testing.allocator, &scanner, .{}),
    );
    try testing.expectEqual(@as(u64, 4), diagnostics.getLine());
}

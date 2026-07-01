const std = @import("std");
const log = std.log.scoped(.diff);

const startsWith = std.mem.startsWith;

pub const Diff = struct {
    files: []FileDiff,
    display_lines: []DisplayLine,
    top_line: usize = 0,

    /// The caller needs to ensure the input stays intact until deinit is
    /// called. The construction of Diff as well as its children makes no
    /// attempt to copy the underlying slices
    pub fn init(
        alloc: std.mem.Allocator,
        input: []const u8,
        width: c_uint,
    ) !Diff {
        var lines = std.mem.splitScalar(u8, input, '\n');
        var files: std.ArrayList(FileDiff) = .empty;

        while (lines.next()) |line| {
            if (!startsWith(u8, line, "diff")) {
                return error.MalformedDiff;
            }

            var buf: std.ArrayList([]const u8) = .empty;
            try buf.append(alloc, line);

            var file_diff: FileDiff = undefined;

            // Parsing meta
            while (true) {
                const peek = lines.peek() orelse break;

                if (startsWith(u8, peek, "@@")) {
                    const slice = try buf.toOwnedSlice(alloc);
                    defer alloc.free(slice);
                    const meta = try parseMeta(slice);

                    file_diff.old_path = meta.old_path;
                    file_diff.new_path = meta.new_path;

                    _ = lines.next();

                    break;
                } else if (startsWith(u8, peek, "diff")) {
                    break;
                }

                const next_line = lines.next().?;
                try buf.append(alloc, next_line);
            }

            // Parse hunks
            var hunks: std.ArrayList(Hunk) = .empty;

            while (true) {
                const peek = lines.peek();

                if (peek == null or startsWith(u8, peek.?, "@@")) {
                    _ = lines.next();
                    if (buf.items.len > 0) {
                        const slice = try buf.toOwnedSlice(alloc);
                        defer alloc.free(slice);

                        const hunk = try parseHunk(alloc, slice);
                        try hunks.append(alloc, hunk);
                    }
                } else if (startsWith(u8, peek.?, "diff")) {
                    break;
                }

                const next_line = lines.next() orelse break;
                try buf.append(alloc, next_line);
            }

            file_diff.hunks = try hunks.toOwnedSlice(alloc);

            try files.append(alloc, file_diff);
        }

        var display_lines: std.ArrayList(DisplayLine) = .empty;
        for (files.items) |file_diff| {
            try file_diff.gatherDisplayLines(alloc, &display_lines, width);
        }

        return .{
            .files = try files.toOwnedSlice(alloc),
            .display_lines = try display_lines.toOwnedSlice(alloc),
        };
    }

    // TODO: refine param list
    pub fn render(self: Diff) void {
        _ = self;
    }

    pub fn deinit(self: Diff, alloc: std.mem.Allocator) void {
        for (self.files) |file| {
            file.deinit(alloc);
        }
        alloc.free(self.files);
        alloc.free(self.display_lines);
    }
};

pub const FileDiff = struct {
    old_path: []const u8,
    new_path: []const u8,
    hunks: []Hunk,

    pub fn deinit(self: FileDiff, alloc: std.mem.Allocator) void {
        for (self.hunks) |hunk| {
            hunk.deinit(alloc);
        }
        alloc.free(self.hunks);
    }

    pub fn gatherDisplayLines(
        self: FileDiff,
        alloc: std.mem.Allocator,
        buf: *std.ArrayList(DisplayLine),
        width: c_uint,
    ) !void {
        for (self.hunks) |hunk| {
            try hunk.gatherDisplayLines(alloc, buf, width);
        }
    }
};

pub const Hunk = struct {
    // TODO: actually parse these info
    old_start: usize = 0,
    old_len: usize = 0,
    new_start: usize = 0,
    new_len: usize = 0,
    lines: []DiffLine,

    pub fn deinit(self: Hunk, alloc: std.mem.Allocator) void {
        alloc.free(self.lines);
    }

    pub fn gatherDisplayLines(
        self: Hunk,
        alloc: std.mem.Allocator,
        buf: *std.ArrayList(DisplayLine),
        width: c_uint,
    ) !void {
        for (self.lines) |line| {
            try line.gatherDisplayLines(alloc, buf, width);
        }
    }
};

pub const DiffLine = union(enum) {
    context: []const u8,
    add: []const u8,
    remove: []const u8,

    pub fn gatherDisplayLines(
        self: DiffLine,
        alloc: std.mem.Allocator,
        buf: *std.ArrayList(DisplayLine),
        width: c_uint,
    ) !void {
        const line = self.intoDisplayLine();
        var remaining = line.text;

        while (wrapLine(remaining, width)) |end| {
            if (end == 0) break;

            try buf.append(alloc, .{
                .kind = line.kind,
                .text = remaining[0..end],
            });
            remaining = remaining[end..];
        }

        if (remaining.len > 0) {
            try buf.append(alloc, .{
                .kind = line.kind,
                .text = remaining,
            });
        }
    }

    fn intoDisplayLine(self: DiffLine) DisplayLine {
        return switch (self) {
            .context => |text| .{ .kind = DisplayLine.Kind.context, .text = text },
            .add => |text| .{ .kind = DisplayLine.Kind.add, .text = text },
            .remove => |text| .{ .kind = DisplayLine.Kind.remove, .text = text },
        };
    }
};

/// An alternate representation of parsed content optmized for rendering
const DisplayLine = struct {
    const Kind = enum {
        file_header,
        hunk_header,
        context,
        add,
        remove,
    };

    kind: Kind,
    text: []const u8,

    pub fn render(self: DisplayLine) void {
        _ = self;
    }
};

/// Does NOT copy
fn parseMeta(inputs: [][]const u8) !struct { old_path: []const u8, new_path: []const u8 } {
    std.debug.assert(inputs.len > 0);

    const first_line = inputs[0];
    var iter = std.mem.splitBackwardsAny(u8, first_line, " ");

    const new_path = iter.next() orelse return error.MalformedMetaInput;
    const old_path = iter.next() orelse return error.MalformedMetaInput;

    return .{
        .old_path = old_path,
        .new_path = new_path,
    };
}

/// Does NOT copy
fn parseHunk(alloc: std.mem.Allocator, inputs: [][]const u8) !Hunk {
    std.debug.assert(inputs.len > 0);

    var lines: std.ArrayList(DiffLine) = .empty;

    for (inputs) |input| {
        var line: DiffLine = undefined;

        if (startsWith(u8, input, " ")) {
            line = .{ .context = input };
        } else if (startsWith(u8, input, "-")) {
            line = .{ .remove = input };
        } else if (startsWith(u8, input, "+")) {
            line = .{ .add = input };
        } else {
            log.err("Unknown line encountered. Skipping", .{});
            continue;
        }

        try lines.append(alloc, line);
    }

    return .{
        .lines = try lines.toOwnedSlice(alloc),
    };
}

// TODO: util candidate
/// Given a slice and a width for display area, produce an optional index of
/// the new end for the current line. If null is returned, the current line is
/// not long enough to create a wrap.
fn wrapLine(input: []const u8, width: c_uint) ?usize {
    if (input.len == 0) return null;

    const max_width: usize = width;
    if (max_width == 0) return 0;

    var cols: usize = 0;
    var i: usize = 0;

    while (i < input.len) {
        const start = i;
        const cp_len = utf8CodepointLen(input[start..]);
        const cp_width = codepointDisplayWidth(input[start .. start + cp_len]);

        if (cols + cp_width > max_width) {
            // If the first codepoint itself is wider than the viewport, return
            // its end so callers can still make progress rather than looping
            // forever on the same input.
            return if (start == 0) cp_len else start;
        }

        cols += cp_width;
        i += cp_len;
    }

    return null;
}

fn utf8CodepointLen(input: []const u8) usize {
    std.debug.assert(input.len > 0);

    const len = std.unicode.utf8ByteSequenceLength(input[0]) catch return 1;
    if (len > input.len) return 1;
    return len;
}

fn codepointDisplayWidth(input: []const u8) usize {
    std.debug.assert(input.len > 0);

    if (input.len == 1) {
        return switch (input[0]) {
            '\t' => 4,
            0x00...0x1f, 0x7f => 0,
            else => 1,
        };
    }

    const cp = std.unicode.utf8Decode(input) catch return 1;
    if (isCombiningCodepoint(cp)) return 0;

    // This intentionally avoids depending on notcurses/libc. It is UTF-8 safe,
    // but not a complete wcwidth implementation; CJK/fullwidth characters are
    // currently treated as width 1. If that matters, replace this helper with a
    // real wcwidth/ncstrwidth-backed implementation.
    return 1;
}

fn isCombiningCodepoint(cp: u21) bool {
    return switch (cp) {
        0x0300...0x036f,
        0x1ab0...0x1aff,
        0x1dc0...0x1dff,
        0x20d0...0x20ff,
        0xfe20...0xfe2f,
        => true,
        else => false,
    };
}

test "parseMeta extracts old and new paths from diff header" {
    var inputs = [_][]const u8{
        "diff --git a/src/components/DiffWindow.zig b/src/components/DiffWindow.zig",
        "index 95a0b682a7..dc2be24e5f 100644",
        "--- a/src/components/DiffWindow.zig",
        "+++ b/src/components/DiffWindow.zig",
    };

    const meta = try parseMeta(&inputs);

    try std.testing.expectEqualStrings("a/src/components/DiffWindow.zig", meta.old_path);
    try std.testing.expectEqualStrings("b/src/components/DiffWindow.zig", meta.new_path);
}

test "parseHunk classifies context add and remove lines" {
    const alloc = std.testing.allocator;

    const context = " const std = @import(\"std\");";
    const add = "+const util = @import(\"../util.zig\");";
    const remove = "-const old = @import(\"old.zig\");";
    var inputs = [_][]const u8{ context, add, remove };

    const hunk = try parseHunk(alloc, &inputs);
    defer hunk.deinit(alloc);

    try std.testing.expectEqual(@as(usize, 3), hunk.lines.len);
    try std.testing.expectEqualStrings(" const std = @import(\"std\");", hunk.lines[0].context);
    try std.testing.expectEqualStrings("+const util = @import(\"../util.zig\");", hunk.lines[1].add);
    try std.testing.expectEqualStrings("-const old = @import(\"old.zig\");", hunk.lines[2].remove);
}

test "wrapLine returns null when line fits" {
    try std.testing.expectEqual(null, wrapLine("abc", 3));
    try std.testing.expectEqual(null, wrapLine("abc", 4));
}

test "wrapLine returns byte index where wrapping should occur" {
    try std.testing.expectEqual(@as(?usize, 3), wrapLine("abcd", 3));
    try std.testing.expectEqual(@as(?usize, 1), wrapLine("abcd", 1));
}

test "wrapLine does not split utf8 codepoints" {
    // é is two bytes, but this implementation treats it as one display column.
    try std.testing.expectEqual(@as(?usize, 3), wrapLine("éab", 2));
}

test "Diff.init parses a single file diff" {
    const input =
        \\diff --git a/src/components/DiffWindow.zig b/src/components/DiffWindow.zig
        \\index 95a0b682a7..dc2be24e5f 100644
        \\--- a/src/components/DiffWindow.zig
        \\+++ b/src/components/DiffWindow.zig
        \\@@ -1,1 +1,3 @@
        \\ const std = @import("std");
        \\+const util = @import("../util.zig");
        \\-const old = @import("old.zig");
        \\
    ;

    const alloc = std.testing.allocator;
    const diff = try Diff.init(alloc, input, 80);
    defer diff.deinit(alloc);

    try std.testing.expectEqual(@as(usize, 1), diff.files.len);
    try std.testing.expectEqualStrings("a/src/components/DiffWindow.zig", diff.files[0].old_path);
    try std.testing.expectEqualStrings("b/src/components/DiffWindow.zig", diff.files[0].new_path);

    try std.testing.expectEqual(@as(usize, 1), diff.files[0].hunks.len);
    try std.testing.expectEqual(@as(usize, 3), diff.files[0].hunks[0].lines.len);
    try std.testing.expectEqualStrings(" const std = @import(\"std\");", diff.files[0].hunks[0].lines[0].context);
    try std.testing.expectEqualStrings("+const util = @import(\"../util.zig\");", diff.files[0].hunks[0].lines[1].add);
    try std.testing.expectEqualStrings("-const old = @import(\"old.zig\");", diff.files[0].hunks[0].lines[2].remove);
}

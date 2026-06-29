const std = @import("std");
const log = std.log.scoped(.diff);

const startsWith = std.mem.startsWith;

pub const Diff = struct {
    files: []FileDiff,

    pub const ParseState = union(enum) {
        FileDiff: FileDiff,
        Hunk: Hunk,
        DiffLine: DiffLine,
    };

    pub fn init(alloc: std.mem.Allocator, input: []const u8) !Diff {
        var lines = std.mem.splitScalar(u8, input, '\n');
        var files: std.ArrayList(FileDiff) = .empty;

        outer: while (lines.next()) |line| {
            if (!startsWith(u8, line, "diff")) {
                return error.MalformedDiff;
            }

            var buf: std.ArrayList([]const u8) = .empty;
            try buf.append(alloc, line);

            var file_diff: FileDiff = undefined;

            // Parsing meta
            while (true) {
                const peek = lines.peek() orelse break :outer;

                if (startsWith(u8, peek, "@@")) {
                    const slice = try buf.toOwnedSlice(alloc);
                    defer alloc.free(slice);
                    const meta = try parseMeta(try buf.toOwnedSlice(alloc));

                    file_diff.old_path = try alloc.dupe(u8, meta.old_path);
                    file_diff.new_path = try alloc.dupe(u8, meta.new_path);

                    _ = lines.next();

                    break;
                } else if (startsWith(u8, peek, "diff")) {
                    continue :outer;
                }

                const next_line = lines.next().?;
                try buf.append(alloc, next_line);
            }

            // Parse hunks
            var hunks: std.ArrayList(Hunk) = .empty;

            while (true) {
                const peek = lines.peek() orelse break :outer;

                if (startsWith(u8, peek, "@@")) {
                    _ = lines.next();
                    if (buf.items.len > 0) {
                        const hunk = try parseHunk(try buf.toOwnedSlice(alloc));
                        try hunks.append(alloc, hunk);
                    }
                } else if (startsWith(u8, peek, "diff")) {
                    continue :outer;
                }

                const next_line = lines.next() orelse break :outer;
                try buf.append(alloc, next_line);
            }

            try files.append(alloc, file_diff);
        }

        return .{
            .files = try files.toOwnedSlice(alloc),
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
    }
};

pub const FileDiff = struct {
    old_path: []const u8,
    new_path: []const u8,
    hunks: []Hunk,

    // TODO: refine param list
    pub fn render(self: FileDiff) void {
        _ = self;
    }

    pub fn deinit(self: FileDiff, alloc: std.mem.Allocator) void {
        for (self.hunks) |hunk| {
            hunk.deinit(alloc);
        }
        alloc.free(self.hunks);
    }
};

pub const Hunk = struct {
    // TODO: actually parse these info
    old_start: usize = 0,
    old_len: usize = 0,
    new_start: usize = 0,
    new_len: usize = 0,
    lines: []DiffLine,

    // TODO: refine param list
    pub fn render(self: Hunk) void {
        _ = self;
    }

    pub fn deinit(self: Hunk, alloc: std.mem.Allocator) void {
        for (self.lines) |line| {
            line.deinit(alloc);
        }
        alloc.free(self.lines);
    }
};

pub const DiffLine = union(enum) {
    context: []const u8,
    add: []const u8,
    remove: []const u8,

    // TODO: refine param list
    pub fn render(self: DiffLine) void {
        _ = self;
    }

    pub fn deinit(self: DiffLine, alloc: std.mem.Allocator) void {
        switch (self) {
            .context => |ctx| alloc.free(ctx),
            .add => |a| alloc.free(a),
            .remove => |r| alloc.free(r),
        }
    }
};

/// Does NOT copy
fn parseMeta(inputs: [][]const u8) !struct { old_path: []const u8, new_path: []const u8 } {
    std.debug.assert(inputs.len > 0);

    const first_line = inputs[0];
    var iter = std.mem.splitBackwardsAny(u8, first_line, ' ');

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

        lines.append(alloc, line);
    }

    return .{
        .lines = try lines.toOwnedSlice(alloc),
    };
}

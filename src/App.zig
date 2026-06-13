const std = @import("std");

const util = @import("util.zig");
const c = util.c;
const DiffWindow = @import("components/DiffWindow.zig");

const Self = @This();
pub const Event = struct {
    pub const EventKind = union(enum) {};

    time: i64,
    kind: EventKind,
};
// TODO: switch out stub return types
pub const KeyHandler = fn (event: Event) ?i32;

alloc: std.mem.Allocator,
diff_window: ?DiffWindow = null,
keymapStacks: std.ArrayList(KeyHandler) = .empty,

pub fn init(alloc: std.mem.Allocator) Self {
    return .{
        .alloc = alloc,
    };
}

pub fn deinit(self: Self) void {
    _ = self;
}

pub fn update(self: *Self, events: []Event) !void {
    _ = self;
    _ = events;
}

pub fn render(self: *const Self) !void {
    _ = self;
}

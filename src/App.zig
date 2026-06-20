const std = @import("std");

const util = @import("util.zig");
const c = util.c;
const DiffWindow = @import("components/DiffWindow.zig");

const protocol = @import("protocol.zig");
const InputEvent = protocol.InputEvent;
const Receiver = util.Spsc(InputEvent).Receiver;

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
rx: Receiver,
future: ?std.Io.Future(anyerror!void) = null,

pub fn init(alloc: std.mem.Allocator, rx: Receiver) Self {
    return .{
        .alloc = alloc,
        .rx = rx,
    };
}

pub fn start(self: *Self, io: std.Io) !void {
    self.future = try std.Io.concurrent(io, coreLoop, .{ self, io });
}

pub fn deinit(self: Self, io: std.Io) void {
    if (self.future) |fut| {
        fut.cancel(io) catch {
            // TODO: log this
        };
    }
}

fn coreLoop(self: *Self, io: std.Io) !void {
    while (true) {
        try io.checkCancel();

        const ev = try self.rx.recv(io);

        switch (ev) {}
    }
}

fn update(self: *Self, events: []Event) !void {
    _ = self;
    _ = events;
}

fn render(self: *const Self) !void {
    _ = self;
}

test "app init" {}

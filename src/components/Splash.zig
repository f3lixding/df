//! This is the base component for the app and will always be spawned first at
//! the bottom and only at the bottom of the stack.
const std = @import("std");

const util = @import("../util.zig");
const c = util.c;
const protocol = @import("../protocol.zig");
const FrameTime = protocol.FrameTime;
const Conclusion = protocol.Conclusion;
const Component = @import("Component.zig");

const Self = @This();

pub fn initInterface(self: *Self) Component {
    return .{
        .ptr = self,
        .vtable = &.{
            .render = struct {
                pub fn _render(ptr: *anyopaque, nc_ctx: *c.notcurses) !void {
                    const self_typed: *Self = @ptrCast(@alignCast(ptr));
                    try @call(.always_inline, render, .{ self_typed, nc_ctx });
                }
            }._render,
        },
    };
}

pub fn init(nc_ctx: *c.notcurses) !Self {
    // Note (to be deleted later, this is just a reminder):
    // - Things that we need to start receiving input events and process them
    const stdplane = c.notcurses_stdplane(nc_ctx) orelse return error.CannotObtainStdplane;
    _ = stdplane;
}

pub fn render(self: *const Self, nc_ctx: *c.notcurses) !void {
    _ = self;
    _ = nc_ctx;
}

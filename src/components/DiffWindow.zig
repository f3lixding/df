const std = @import("std");

const util = @import("../util.zig");
const consts = @import("../consts.zig");
const c = util.c;
const protocol = @import("../protocol.zig");
const InputEvent = protocol.InputEvent;
const FrameTime = protocol.FrameTime;
const Conclusion = protocol.Conclusion;
const Component = @import("Component.zig");
const Bucket = util.LeakyBucket(InputEvent);
const RenderCtx = protocol.RenderCtx;
const ASSET_PATH = consts.ASSET_PATH;

const Self = @This();

const DIFF_COMMAND: []const u8 = "jj diff --tool=:git --color never";

dirty: bool = false,

pub fn initInterface(self: *Self) !Component {
    return .{
        .ptr = self,
        .vtable = &.{
            .render = struct {
                pub fn _render(ptr: *anyopaque, render_ctx: *const RenderCtx, nc_ctx: *c.notcurses) !void {
                    const self_typed: *Self = @ptrCast(@alignCast(ptr));
                    try @call(.always_inline, render, .{ self_typed, render_ctx, nc_ctx });
                }
            }._render,

            .is_dirty = struct {
                pub fn isDirty(ptr: *anyopaque) bool {
                    const self_typed: *Self = @ptrCast(@alignCast(ptr));
                    return self_typed.dirty;
                }
            }.isDirty,

            .key_handler = struct {
                pub fn handleInput(ptr: *anyopaque, event: InputEvent) !Conclusion {
                    const self_typed: *Self = @ptrCast(@alignCast(ptr));
                    return try @call(.always_inline, handleInputEvent, .{ self_typed, event });
                }
            }.handleInput,

            .update = struct {
                pub fn _update(ptr: *anyopaque, ft: FrameTime) !Conclusion {
                    const self_typed: *Self = @ptrCast(@alignCast(ptr));
                    return try @call(.always_inline, update, .{ self_typed, ft });
                }
            }._update,
        },
    };
}

pub fn init() Self {}

pub fn deinit() void {}

pub fn handleInputEvent() void {}

pub fn render() void {}

pub fn update() void {}

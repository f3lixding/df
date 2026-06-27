//! This is the base component for the app and will always be spawned first at
//! the bottom and only at the bottom of the stack.
const std = @import("std");

const util = @import("../util.zig");
const c = util.c;
const protocol = @import("../protocol.zig");
const InputEvent = protocol.InputEvent;
const FrameTime = protocol.FrameTime;
const Conclusion = protocol.Conclusion;
const Component = @import("Component.zig");
const Bucket = util.LeakyBucket(InputEvent);
const RenderCtx = protocol.RenderCtx;

const Self = @This();

input_bucket: Bucket,
initial_render_done: bool = false,

pub fn initInterface(self: *Self) Component {
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
                    if (!self_typed.initial_render_done) {
                        self_typed.initial_render_done = true;
                        return true;
                    }
                    return false;
                }
            }.isDirty,

            .key_handler = struct {
                pub fn handleInput(ptr: *anyopaque, event: InputEvent) !Conclusion {
                    const self_typed: *Self = @ptrCast(@alignCast(ptr));
                    return try @call(.always_inline, handleInputEvent, .{ self_typed, event });
                }
            }.handleInput,
        },
    };
}

pub fn init() Self {
    const input_bucket = Bucket.init(.{});

    return .{
        .input_bucket = input_bucket,
    };
}

pub fn handleInputEvent(self: *Self, input_event: InputEvent) !Conclusion {
    const key = input_event.key;

    switch (key) {
        'q' => return .Quit,
        c.NCKEY_RESIZE => {
            self.initial_render_done = false;
        },
        else => {},
    }

    return .Noop;
}

pub fn render(self: *const Self, render_ctx: *const RenderCtx, nc_ctx: *c.notcurses) !void {
    _ = self;

    const rows = render_ctx.rows;
    const cols = render_ctx.cols;

    const stdplane = c.notcurses_stdplane(nc_ctx) orelse return error.NoStdplane;

    c.ncplane_erase(stdplane);

    const logo = [_][:0]const u8{
        "     ____  ______ ",
        "    / __ \\/ ____/",
        "   / / / / /_     ",
        "  / /_/ / __/     ",
        " /_____/_/        ",
    };
    const title: [:0]const u8 = "doodle finder";
    const hint: [:0]const u8 = "press j/f, resize the terminal, make something messy";

    const logo_width: c_uint = logo[0].len;
    const block_height: c_uint = logo.len + 4;
    const origin_y = centered(rows, block_height);
    const origin_x = centered(cols, logo_width);

    if (c.ncplane_set_fg_rgb8(stdplane, 0x85, 0xd7, 0xff) < 0) return error.SetColorFailed;
    c.ncplane_set_styles(stdplane, c.NCSTYLE_BOLD);

    for (logo, 0..) |line, i| {
        const y: c_int = origin_y + @as(c_int, @intCast(i));
        if (c.ncplane_putstr_yx(stdplane, y, origin_x, line.ptr) < 0) {
            return error.PutStrFailed;
        }
    }

    c.ncplane_set_styles(stdplane, c.NCSTYLE_NONE);
    if (c.ncplane_set_fg_rgb8(stdplane, 0xff, 0xd8, 0x66) < 0) return error.SetColorFailed;
    try putCentered(stdplane, origin_y + @as(c_int, @intCast(logo.len)) + 1, cols, title);

    if (c.ncplane_set_fg_rgb8(stdplane, 0x88, 0x88, 0x88) < 0) return error.SetColorFailed;
    try putCentered(stdplane, origin_y + @as(c_int, @intCast(logo.len)) + 3, cols, hint);
}

fn centered(outer: c_uint, inner: c_uint) c_int {
    if (outer <= inner) return 0;
    return @intCast((outer - inner) / 2);
}

fn putCentered(plane: *c.ncplane, y: c_int, cols: c_uint, text: [:0]const u8) !void {
    const text_width: c_uint = @intCast(text.len);
    const x = centered(cols, text_width);
    if (c.ncplane_putstr_yx(plane, y, x, text.ptr) < 0) {
        return error.PutStrFailed;
    }
}

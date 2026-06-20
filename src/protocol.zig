const util = @import("util.zig");
const c = util.c;

pub const InputEvent = struct {
    key: u32,
    ncinput: c.ncinput,
};

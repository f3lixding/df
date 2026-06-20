const util = @import("util.zig");
const c = util.c;

pub const InputEvent = struct {
    timestamp: i64,
    key: u32,
    ncinput: c.ncinput,
};

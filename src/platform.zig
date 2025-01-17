const std = @import("std");
const builtin = @import("builtin");
const stygian = @import("stygian_platform");
const log = stygian.log;

pub const os = if (builtin.os.tag != .emscripten) std.os else struct {
    pub const heap = struct {
        pub const page_allocator = std.heap.c_allocator;
    };
};

// This configures log level for the platform
pub const log_options = log.Options{
    .level = .Info,
};

const platform_start = stygian.platform.start.platform_start;
pub fn main() !void {
    try platform_start();
}

const Config = struct {
    reg_start: u64,
    offset: u32,
    value: u32,
};

var rebootConfig: ?Config = null;
var poweroffConfig: ?Config = null;

pub fn initReboot(reg_start: u64, offset: u32, value: u32) void {
    rebootConfig = Config{
        .reg_start = reg_start,
        .offset = offset,
        .value = value,
    };
}

pub fn initPoweroff(reg_start: u64, offset: u32, value: u32) void {
    poweroffConfig = Config{
        .reg_start = reg_start,
        .offset = offset,
        .value = value,
    };
}

pub fn reboot() noreturn {
    doOrDie("reboot", rebootConfig);
}

pub fn poweroff() noreturn {
    doOrDie("poweroff", poweroffConfig);
}

fn doOrDie(comptime name: []const u8, maybe_config: ?Config) noreturn {
    const config = maybe_config orelse @panic("syscon " ++ name ++ " not configured!");
    @import("../console/fb.zig").printf("writing {x:0>4} to {x:0>8}+{x:0>4}\n", .{ config.value, config.reg_start, config.offset });
    @intToPtr(*volatile u32, config.reg_start + config.offset).* = config.value;
    var i: usize = 0;
    while (i < 100_000_000) : (i += 1) asm volatile ("nop");
    @panic("syscon " ++ name ++ " returned");
}

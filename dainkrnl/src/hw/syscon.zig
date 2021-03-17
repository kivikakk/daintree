const printf = @import("../console/fb.zig").printf;

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
    printf("goodbye\n", .{});
    @intToPtr(*volatile u32, config.reg_start + config.offset).* = config.value;
    @panic("syscon " ++ name ++ " returned");
}

const printf = @import("../console/fb.zig").printf;
const paging = @import("../paging.zig");

const Config = struct {
    offset: u32,
    value: u32,
};

var regBase: ?u64 = null;
var rebootConfig: ?Config = null;
var poweroffConfig: ?Config = null;

pub fn init(base: u64) void {
    regBase = paging.mapPage(base, .peripheral) catch @panic("couldn't map syscon");
}

pub fn initReboot(offset: u32, value: u32) void {
    rebootConfig = Config{
        .offset = offset,
        .value = value,
    };
}

pub fn initPoweroff(offset: u32, value: u32) void {
    poweroffConfig = Config{
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
    const reg_base = regBase orelse @panic("syscon base register not configured!");
    const config = maybe_config orelse @panic("syscon " ++ name ++ " not configured!");

    printf("goodbye\n", .{});
    @as(*volatile u32, @ptrFromInt(reg_base + config.offset)).* = config.value;
    @panic("syscon " ++ name ++ " returned");
}

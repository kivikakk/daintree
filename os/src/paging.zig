// ref Figure D5-15
fn PageTableEntry_u64(pte: PageTableEntry) u64 {
    return @as(u64, pte.valid) |
        (@as(u64, @enumToInt(pte.type)) << 1) |
        (@as(u64, pte.lba.attr_indx) << 2) |
        (@as(u64, pte.lba.ns) << 5) |
        (@as(u64, pte.lba.ap) << 6) |
        (@as(u64, pte.lba.sh) << 8) |
        (@as(u64, pte.lba.af) << 10) |
        (@as(u64, pte.oa) << 29) |
        (@as(u64, pte.uba.pxn) << 53) |
        (@as(u64, pte.uba.uxn) << 54);
}

const PageTableEntry = struct {
    valid: u1 = 1,
    type: enum(u1) {
        block = 0,
        table = 1,
    } = .block,
    lba: struct {
        attr_indx: u3 = 0,
        ns: u1 = 0,
        ap: u2 = 0b00, // R/W, EL0 access denied
        sh: u2 = 0b11, // inner shareable
        af: u1 = 0b1, // access flag (?)
        // ng: u1 = 0, // ??
    } = .{},
    // _res0a: u4 = 0, // OA[51:48]
    // _res0b: u1 = 0, // nT
    // _res0c: u12 = 0,
    oa: u19, // OA[47:29]
    // _res0d: u4 = 0,
    uba: struct {
        // contiguous: u1 = 0,
        pxn: u1 = 0,
        uxn: u1 = 1,
        // _resa: u4 = 0,
        // _res0b: u4 = 0,
        // _resb: u1 = 0,
    } = .{},
};

fn TCR_EL1_u64(tcr: TCR_EL1) u64 {
    return @as(u64, tcr.t0sz) |
        (@as(u64, tcr.epd0) << 7) |
        (@as(u64, tcr.irgn0) << 8) |
        (@as(u64, tcr.orgn0) << 10) |
        (@as(u64, tcr.sh0) << 12) |
        (@as(u64, @enumToInt(tcr.tg0)) << 14) |
        (@as(u64, tcr.t1sz) << 16) |
        (@as(u64, tcr.a1) << 22) |
        (@as(u64, tcr.epd1) << 23) |
        (@as(u64, tcr.irgn1) << 24) |
        (@as(u64, tcr.orgn1) << 26) |
        (@as(u64, tcr.sh1) << 28) |
        (@as(u64, @enumToInt(tcr.tg1)) << 30) |
        (@as(u64, @enumToInt(tcr.ips)) << 32);
}

const TCR_EL1 = struct {
    t0sz: u6 = 25, // TTBR0_EL1 addresses 2**(64-25)
    // _res0a: u1 = 0,
    epd0: u1 = 0, // enable TTBR0_EL1 walks (set = 1 to *disable*)
    irgn0: u2 = 0b01, // "Normal, Inner Wr.Back Rd.alloc Wr.alloc Cacheble"
    orgn0: u2 = 0b01, // "Normal, Outer Wr.Back Rd.alloc Wr.alloc Cacheble"
    sh0: u2 = 0b11, // inner-shareable
    tg0: enum(u2) {
        K4 = 0b00,
        K16 = 0b10,
        K64 = 0b01,
    } = .K4,
    t1sz: u6 = 25, // TTBR1_EL1 addresses 2**(64-25): 0xffffff80_00000000
    a1: u1 = 0, // TTBR0_EL1.ASID defines the ASID
    epd1: u1 = 0, // enable TTBR1_EL1 walks (set = 1 to *disable*)
    irgn1: u2 = 0b01, // "Normal, Inner Wr.Back Rd.alloc Wr.alloc Cacheble"
    orgn1: u2 = 0b01, // "Normal, Outer Wr.Back Rd.alloc Wr.alloc Cacheble"
    sh1: u2 = 0b11, // inner-shareable
    tg1: enum(u2) { // granule size for TTBR1_EL1
        K4 = 0b10,
        K16 = 0b01,
        K64 = 0b11,
    } = .K4,
    ips: enum(u3) {
        B32 = 0b000,
        B36 = 0b001,
        B48 = 0b101,
    } = .B36,
    // _res0b: u1 = 0,
    // _as: u1 = 0,
    // tbi0: u1 = 0, // top byte ignored
    // tbi1: u1 = 0,
    // _ha: u1 = 0,
    // _hd: u1 = 0,
    // _hpd0: u1 = 0,
    // _hpd1: u1 = 0,
    // _hwu: u8 = 0,
    // _tbid0: u1 = 0,
    // _tbid1: u1 = 0,
    // _nfd0: u1 = 0,
    // _nfd1: u1 = 0,
    // _res0c: u9 = 0,
};

comptime {
    if (@bitSizeOf(PageTableEntry) != 64) {
        // @compileLog("PageTableEntry misshapen; ", @bitSizeOf(PageTableEntry));
    }
    if (@sizeOf(PageTableEntry) != 8) {
        // @compileLog("PageTableEntry misshapen; ", @sizeOf(PageTableEntry));
    }

    if (@bitSizeOf(TCR_EL1) != 64) {
        // @compileLog("TCR_EL1 misshapen; ", @bitSizeOf(TCR_EL1));
    }
}

fn misc() void {
    var page_table_0: [*]u64 align(0x1000) = undefined;
    var page_table_1: [*]u64 align(0x1000) = undefined;
    check("allocatePages", boot_services.allocatePages(.AllocateAnyPages, .LoaderData, 16, @ptrCast(*[*]align(4096) u8, &page_table_0)));
    printf(buf[0..], "allocated 16x4KiB pages at 0x{x:0>16} for page table 0\r\n", .{page_table_0});
    check("allocatePages", boot_services.allocatePages(.AllocateAnyPages, .LoaderData, 16, @ptrCast(*[*]align(4096) u8, &page_table_1)));
    printf(buf[0..], "allocated 16x4KiB pages at 0x{x:0>16} for page table 1\r\n", .{page_table_1});
    {
        var i: u14 = 0;
        while (i < 8192) : (i += 1) {
            page_table_0[0..8192][i] = PageTableEntry_u64(.{
                .oa = i, // 512MB increments
            });
            page_table_1[0..8192][i] = PageTableEntry_u64(.{ .oa = i });

            if (i < 2) {
                printf(buf[0..], "i{}: {x:0>16}\r\n", .{ i, page_table_0[0..8192][i] });
            }
        }
    }

    const tcr_el1 = TCR_EL1_u64(.{});
    printf(buf[0..], "TCR_EL: {x:0>16}\r\n", .{tcr_el1});
}
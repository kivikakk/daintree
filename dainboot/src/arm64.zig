const dcommon = @import("common/dcommon.zig");

pub fn halt() noreturn {
    asm volatile ("msr daifset, #15");
    while (true) {
        asm volatile ("wfi");
    }
}

pub fn transfer(entry_data: *dcommon.EntryData, uart_base: u64, adjusted_entry: u64) callconv(.Inline) noreturn {
    // Check for EL2: we get
    // and pass to DAINKRNL.
    asm volatile (
    // For QEMU's sake: clear x29, x30. (? Still need this on U-Boot ?)
    // EDK2 trips over when generating stacks otherwise.
        \\mov x29, xzr
        \\mov x30, xzr

        // Disable MMU, alignment checking, SP alignment checking;
        // set little endian in EL0 and EL1.
        \\mov x10, #0x0800
        \\movk x10, #0x30d0, lsl #16
        \\msr sctlr_el1, x10
        \\isb

        // Check if other cores are running.
        \\mrs x10, mpidr_el1
        \\and x10, x10, #3
        \\cbz x10, .cpu_zero

        // Non-zero core
        \\mov x10, #0x44       // XXX Record progress "D"
        \\strb w10, [x7]       // XXX
        \\1: wfe
        \\b 1b

        // Check if we're in EL1 (EDK2 does this for us).
        // If so, go straight to DAINKRNL.
        \\.cpu_zero:
        \\mrs x10, CurrentEL
        \\cmp x10, #0x4
        \\b.ne .not_el1
        \\mov x10, #0x45       // XXX Record progress "E"
        \\strb w10, [x7]       // XXX
        \\br x9

        // Assert we are in EL2.
        \\.not_el1:
        \\cmp x10, #0x8
        \\b.eq .el2
        \\brk #1

        // U-Boot leaves us in EL2. Prepare to eret down to EL1
        // to DAINKRNL.
        \\.el2:

        // Copy our stack.
        \\mov x10, sp
        \\msr sp_el1, x10

        // Don't trap EL0/EL1 accesses to the EL1 physical counter and timer registers.
        \\mrs x10, cnthctl_el2
        \\orr x10, x10, #3
        \\msr cnthctl_el2, x10

        // Reset virtual offset register.
        \\msr cntvoff_el2, xzr

        // Set EL1 execution state to AArch64, not AArch32.
        \\mov x10, #(1 << 31)
        // EL1 execution of DC ISW performs the same invalidation as DC CISW.
        \\orr x10, x10, #(1 << 1)
        \\msr hcr_el2, x10
        \\mrs x10, hcr_el2

        // Clear hypervisor system trap register.
        \\msr hstr_el2, xzr

        // I saw someone on StackOverflow set this this way.
        // "The CPTR_EL2 controls trapping to EL2 for accesses to CPACR, Trace functionality
        // and registers associated with Advanced SIMD and floating-point execution. It also
        // controls EL2 access to this functionality."
        // This sets TFP to 0, TCPAC to 0, and everything else to RES values.
        \\mov x10, #0x33ff
        \\msr cptr_el2, x10

        // Allow EL0/1 to use Advanced SIMD and FP.
        // https://developer.arm.com/documentation/100442/0100/register-descriptions/aarch64-system-registers/cpacr-el1--architectural-feature-access-control-register--el1
        // Set FPEN, [21:20] to 0b11.
        \\mov x10, #0x300000
        \\msr CPACR_EL1, x10

        // Prepare the simulated exception.
        // Trying EL1t (0x3c4) didn't make a difference in practice.
        \\mov x10, #0x3c5            // DAIF+EL1+h (h = 0b1 = use SP_ELx, not SP0)
        \\msr spsr_el2, x10

        // Prepare the return address.
        \\adr x10, .eret_target
        \\msr elr_el2, x10
        \\mov x10, #0x46       // XXX Record progress "F"
        \\strb w10, [x7]       // XXX

        // Fire.
        \\eret
        \\brk #1               // Should not execute; if it did, U-Boot would say hi.

        // Are we in EL1 yet?
        \\.eret_target:
        \\br x9
        :
        : [entry_data] "{x0}" (entry_data),
          [uart_base] "{x7}" (uart_base),

          [entry] "{x9}" (adjusted_entry)
        : "memory"
    );
    unreachable;
}

pub fn cleanInvalidateDCacheICache(start: u64, len: u64) callconv(.Inline) void {
    // Clean and invalidate D- and I-caches for loaded code.
    // https://developer.arm.com/documentation/den0024/a/Caches/Cache-maintenance
    // Also consider referecing https://gitlab.denx.de/u-boot/u-boot/blob/master/arch/arm/cpu/armv8/cache.S,
    // but it uses set/way.
    // See also https://android.googlesource.com/kernel/msm.git/+/android-msm-anthias-3.10-lollipop-wear-release/arch/arm64/mm/cache.S.
    // This used DSB SY instead of ISH, and we will too, just in case.
    asm volatile (
        \\  ADD x1, x1, x0                // Base Address + Length
        \\  MRS X2, CTR_EL0               // Read Cache Type Register
        \\  // Get the minimun data cache line
        \\  //
        \\  UBFX X4, X2, #16, #4          // Extract DminLine (log2 of the cache line)
        \\  MOV X3, #4                    // Dminline iss the number of words (4 bytes)
        \\  LSL X3, X3, X4                // X3 should contain the cache line
        \\  SUB X4, X3, #1                // get the mask for the cache line
        \\
        \\  BIC X4, X0, X4                // Aligned the base address of the region
        \\1:
        \\  DC CVAU, X4                   // Clean data cache line by VA to PoU
        \\  ADD X4, X4, X3                // Next cache line
        \\  CMP X4, X1                    // Is X4 (current cache line) smaller than the end
        \\                                // of the region
        \\  B.LT 1b                       // while (address < end_address)
        \\
        \\  DSB SY                        // Ensure visibility of the data cleaned from cache
        \\
        \\  //
        \\  //Clean the instruction cache by VA
        \\  //
        \\
        \\  // Get the minimum instruction cache line (X2 contains ctr_el0)
        \\  AND X2, X2, #0xF             // Extract IminLine (log2 of the cache line)
        \\  MOV X3, #4                   // IminLine is the number of words (4 bytes)
        \\  LSL X3, X3, X2               // X3 should contain the cache line
        \\  SUB x4, x3, #1               // Get the mask for the cache line
        \\
        \\  BIC X4, X0, X4               // Aligned the base address of the region
        \\2:
        \\  IC IVAU, X4                  // Clean instruction cache line by VA to PoU
        \\  ADD X4, X4, X3               // Next cache line
        \\  CMP X4, X1                   // Is X4 (current cache line) smaller than the end
        \\                               // of the region
        \\  B.LT 2b                      // while (address < end_address)
        \\
        \\  DSB SY                       // Ensure completion of the invalidations
        \\  ISB                          // Synchronize the fetched instruction stream
        :
        : [start] "{x0}" (start),
          [len] "{x1}" (len)
        : "memory", "x2", "x3", "x4"
    );
}

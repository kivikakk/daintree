/* SPDX-License-Identifier: GPL-2.0+ */
/*
 * U-Boot riscv64 EFI linker script
 *
 * SPDX-License-Identifier:     BSD-2-Clause
 *
 * Modified from arch/arm/lib/elf_aarch64_efi.lds
 */
/**
 * Daintree note:
 * Sourced from
 * https://source.denx.de/u-boot/u-boot/-/blob/52ba373b7825e9feab8357065155cf43dfe2f4ff/arch/riscv/lib/elf_riscv64_efi.lds
 * May god have mercy on my soul.
 */

OUTPUT_FORMAT("elf64-littleriscv", "elf64-littleriscv", "elf64-littleriscv")
OUTPUT_ARCH(riscv)
ENTRY(_start)
SECTIONS
{
        .text 0x0 : {
                _text = .;
                *(.text.head)
                *(.text)
                *(.text.*)
                *(.gnu.linkonce.t.*)
                *(.srodata)
                *(.rodata*)
                . = ALIGN(16);
        }
        _etext = .;
        _text_size = . - _text;
        .dynamic  : { *(.dynamic) }
        .data : {
                _data = .;
                *(.sdata)
                *(.data)
                *(.data1)
                *(.data.*)
                *(.got.plt)
                *(.got)

                /*
                 * The EFI loader doesn't seem to like a .bss section, so we
                 * stick it all into .data:
                 */
                . = ALIGN(16);
                _bss = .;
                *(.sbss)
                *(.scommon)
                *(.dynbss)
                *(.bss)
                *(.bss.*)
                *(COMMON)
                . = ALIGN(16);
                _bss_end = .;
        }
        .rela.dyn : { *(.rela.dyn) }
        .rela.plt : { *(.rela.plt) }
        .rela.got : { *(.rela.got) }
        .rela.data : { *(.rela.data) *(.rela.data*) }

        /*
         * Put _edata here so it all gets loaded by U-Boot.
         * The script originally had this equal to _bss_end, but
         * our .rela.dyn wasn't getting loaded into memory so we
         * couldn't do any relocations.
         *
         * Here be dragons.  Do we need .dynsym/.dynstr too?
         */
        _edata = .;
        _data_size = . - _etext;

        . = ALIGN(4096);
        .dynsym   : { *(.dynsym) }
        . = ALIGN(4096);
        .dynstr   : { *(.dynstr) }
        . = ALIGN(4096);
        .note.gnu.build-id : { *(.note.gnu.build-id) }
        /DISCARD/ : {
                *(.rel.reloc)
                *(.eh_frame)
                *(.note.GNU-stack)
        }
        .comment 0 : { *(.comment) }
}

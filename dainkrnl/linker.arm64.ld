ENTRY(daintree_mmu_start)
OUTPUT_FORMAT(elf64-aarch64)

SECTIONS {
    . = 0xffffff8000000000;

    __daintree_base = .;
    .text : {
        *(.text.exceptions)
        *(.text*)
    }

    . = ALIGN(0x1000);

    __daintree_rodata_base = .;
    .eh_frame : { *(.eh_frame) }
    .rodata : { *(.rodata*) }

    . = ALIGN(0x1000);

    __daintree_data_base = .;
    .data : {
        *(.sdata*)
        *(.data*)
    }

    .bss : ALIGN(0x1000) {
        *(.sbss*)
        *(.bss*)
    }

    . = ALIGN(0x1000);
    __daintree_end = .;
}

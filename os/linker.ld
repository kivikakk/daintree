ENTRY(daintree_start)
OUTPUT_FORMAT(elf64-aarch64)

SECTIONS {
    . = 0xffffff8000000000;
    
    __daintree_base = .;
    .text : {
        *(.text)
    }
    .rodata : ALIGN(0x1000) {
        *(.rodata)
    }
    .data : ALIGN(0x1000) {
        *(.data)
    }
    .bss : ALIGN(0x1000) {
        *(.bss)
    }

    . = ALIGN(0x1000);
    __daintree_end = .;
}

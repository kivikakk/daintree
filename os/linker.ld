ENTRY(daintree_start)
OUTPUT_FORMAT(elf64-aarch64)

SECTIONS {
    /* check this address */
    /* .text (0xffff800000000000) : ALIGN(0x1000) { */
    .text (0x40000000) : ALIGN(0x1000) {
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
}

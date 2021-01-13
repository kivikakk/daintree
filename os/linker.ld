ENTRY(daintree_start)
OUTPUT_FORMAT(elf64-aarch64)

SECTIONS {
    .text (0x100000) : ALIGN(0x1000) {
        *(.text)
    }
    .data : ALIGN(0x1000) {
        *(.data)
    }
    .bss : ALIGN(0x1000) {
        *(.bss)
    }
}

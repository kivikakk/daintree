cd "$(dirname "$0")"
objdump -dSl --prefix=. --prefix-strip=4 dainkrnl/zig-out/bin/dainkrnl.qemu_riscv64|less

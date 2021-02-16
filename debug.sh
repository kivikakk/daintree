cd "$(dirname "$0")"
gdb os/zig-cache/bin/dainkrnl.qemu -ex 'set substitute-path /Users/kameliya/Code/daintree/os os' -ex 'set arch aarch64' -ex 'target remote :1234'

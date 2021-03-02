cd "$(dirname "$0")"
gdb dainkrnl/zig-cache/bin/dainkrnl.qemu -ex 'set substitute-path /Users/kameliya/Code/daintree/dainkrnl dainkrnl' -ex 'set arch aarch64' -ex 'target remote :1234'

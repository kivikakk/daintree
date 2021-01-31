cd "$(dirname "$0")"
gdb os/zig-cache/bin/dainkrnl -ex 'directory os/src' -ex 'directory os/src/console' -ex 'set arch aarch64' -ex 'target remote :1234'

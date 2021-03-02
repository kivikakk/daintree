cd "$(dirname "$0")"
objdump -dSl --prefix=. --prefix-strip=4 dainkrnl/zig-cache/bin/dainkrnl|less

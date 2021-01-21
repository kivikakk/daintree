.PHONY: qemu mk-ovmf-vars mk-disk

qemu: dainboot/dainboot.cdr disk.dmg
	qemu-system-aarch64 \
		-accel hvf \
		-m 512 \
		-cpu cortex-a57 -M virt,highmem=off \
		-drive file=/opt/homebrew/share/qemu/edk2-aarch64-code.fd,if=pflash,format=raw,readonly=on \
		-drive file=ovmf_vars.fd,if=pflash,format=raw \
		-serial stdio \
		-drive if=none,file=disk.dmg,format=raw,id=hd0 \
		-cdrom dainboot/dainboot.cdr \
		-device virtio-blk-device,drive=hd0,serial="dummyserial" \
		-device virtio-net-device,netdev=net0 \
		-netdev user,id=net0 \
		-vga none \
		-device ramfb \
		-device usb-ehci \
		-device usb-kbd \
		-device usb-mouse \
		-usb \
		-s

os/zig-cache/bin/dainkrnl: os/build.zig os/version.zig os/linker.ld os/src/*.zig
	cd os && zig build

disk.dmg: os/zig-cache/bin/dainkrnl
	hdiutil attach -mountpoint target disk.dmg
	cp os/zig-cache/bin/dainkrnl target
	hdiutil detach target

dainboot/disk/EFI/BOOT/BOOTAA64.efi: dainboot/build.zig dainboot/version.zig dainboot/src/*.zig
	cd dainboot && zig build

dainboot/dainboot.cdr: dainboot/disk/EFI/BOOT/BOOTAA64.efi
	hdiutil create -fs fat32 -ov -size 48m -volname DAINTREE -format UDTO -srcfolder dainboot/disk dainboot/dainboot.cdr

mk-ovmf-vars:
	dd if=/dev/zero conv=sync bs=1m count=64 of=ovmf_vars.fd

mk-disk:
	hdiutil create -fs fat32 -size 128m -layout GPTSPUD -volname DAINDISK disk.dmg


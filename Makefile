.PHONY: qemu mk-ovmf-vars mk-disk

QEMU_CMD = qemu-system-aarch64 \
		-accel hvf \
		-m 512 \
		-cpu cortex-a53 -M virt,highmem=off \
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

tftp: dainboot/zig-cache/bin/BOOTAA64.rockpro64.efi os/zig-cache/bin/dainkrnl.rockpro64
	tools/update-tftp

qemu: dainboot/dainboot.cdr disk.dmg
	$(QEMU_CMD) -s $$EXTRA_ARGS
	
dtb/qemu.dtb:
	$(QEMU_CMD) -machine dumpdtb=$@
	dtc $@ -o $@

%.dts:
	dtc -I dtb -O dts $*

OS_FILES=$(shell find os -name zig-cache -prune -o -type f) $(shell find common -type f)
os/zig-cache/bin/dainkrnl.%: $(OS_FILES)
	cd os && zig build -Dboard=$*

disk.dmg: os/zig-cache/bin/dainkrnl.qemu
	hdiutil attach -mountpoint target disk.dmg
	cp $< target/dainkrnl
	cp dtb/qemu.dtb target/dtb
	hdiutil detach target

DAINBOOT_FILES=$(shell find dainboot -name zig-cache -prune -o -type f -name \*.zig) $(shell find common -type f)
dainboot/zig-cache/bin/BOOTAA64.%.efi: $(DAINBOOT_FILES)
	cd dainboot && zig build -Dboard=$*

dainboot/disk/EFI/BOOT/BOOTAA64.efi: dainboot/zig-cache/bin/BOOTAA64.qemu.efi
	cp $< $@

dainboot/dainboot.cdr: dainboot/disk/EFI/BOOT/BOOTAA64.efi
	hdiutil create -fs fat32 -ov -size 48m -volname DAINTREE -format UDTO -srcfolder dainboot/disk dainboot/dainboot.cdr

mk-ovmf-vars:
	dd if=/dev/zero conv=sync bs=1m count=64 of=ovmf_vars.fd

mk-disk:
	hdiutil create -fs fat32 -size 128m -layout GPTSPUD -volname DAINDISK disk.dmg

ci: dainboot/zig-cache/bin/BOOTAA64.qemu.efi \
	dainboot/zig-cache/bin/BOOTAA64.rockpro64.efi \
	os/zig-cache/bin/dainkrnl.qemu \
	os/zig-cache/bin/dainkrnl.rockpro64 \

clean:
	-rm -rf dtb/zig-cache os/zig-cache dainboot/zig-cache

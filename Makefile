.PHONY: qemu mk-ovmf-vars mk-disk

QEMU_CMD = $$HOME/Code/qemu/build/qemu-system-aarch64 \
		-dtb dtb/qemu.dtb \
		-accel hvf \
		-m 512 \
		-cpu cortex-a53 -M virt,highmem=off \
		-bios u-boot.bin \
		-serial stdio \
		-drive file=fat:rw:target/disk,format=raw \
		-device virtio-net-device,netdev=net0 \
		-netdev user,id=net0 \
		-vga none \
		-device ramfb \
		-device usb-ehci \
		-device usb-kbd \
		-device usb-mouse \
		-usb \
		-fw_cfg opt/test,string=hello \

tftp: dainboot/zig-cache/bin/BOOTAA64.rockpro64.efi os/zig-cache/bin/dainkrnl.rockpro64
	tools/update-tftp

qemu: ovmf_vars.fd target/disk/EFI/BOOT/BOOTAA64.efi target/disk/dainkrnl target/disk/dtb
	$(QEMU_CMD) -s $$EXTRA_ARGS
	
dtb/qemu.dtb:
	$(QEMU_CMD) -machine dumpdtb=$@
	dtc $@ -o $@

OS_FILES=$(shell find os -name zig-cache -prune -o -type f) $(shell find common -type f)
os/zig-cache/bin/dainkrnl.%: $(OS_FILES)
	cd os && zig build -Dboard=$*

target/disk/dainkrnl: os/zig-cache/bin/dainkrnl.qemu
	mkdir -p $(@D)
	cp $< $@

target/disk/dtb: dtb/qemu.dtb
	mkdir -p $(@D)
	cp $< $@

DAINBOOT_FILES=$(shell find dainboot -name zig-cache -prune -o -type f -name \*.zig) $(shell find common -type f)
dainboot/zig-cache/bin/BOOTAA64.%.efi: $(DAINBOOT_FILES)
	cd dainboot && zig build -Dboard=$*

target/disk/EFI/BOOT/BOOTAA64.efi: dainboot/zig-cache/bin/BOOTAA64.qemu.efi
	mkdir -p $(@D)
	cp $< $@

ovmf_vars.fd:
	dd if=/dev/zero conv=sync bs=1048576 count=64 of=ovmf_vars.fd

CI_EDK2=/usr/local/share/qemu/edk2-aarch64-code.fd
CI_QEMU_ACCEL=tcg

ci: dainboot/zig-cache/bin/BOOTAA64.qemu.efi \
	dainboot/zig-cache/bin/BOOTAA64.rockpro64.efi \
	os/zig-cache/bin/dainkrnl.qemu \
	os/zig-cache/bin/dainkrnl.rockpro64 \
	ovmf_vars.fd \
	target/disk/dainkrnl target/disk/dtb target/disk/EFI/BOOT/BOOTAA64.efi
	env CI_EDK2=$(CI_EDK2) CI_QEMU_ACCEL="$(CI_QEMU_ACCEL)" tools/ci-expect

clean:
	-rm -rf dtb/zig-cache os/zig-cache dainboot/zig-cache target

%.dts:
	dtc -I dtb -O dts $*

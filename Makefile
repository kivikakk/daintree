.PHONY: qemu

QEMU_ACCEL := tcg
ifeq ($OS),Windows NT)
else
	UNAME_S := $(shell uname -s)
	ifeq ($(UNAME_S),Darwin)
		QEMU_ACCEL := hvf
	endif
endif

QEMU_CMD = qemu-system-aarch64 \
		-dtb dtb/qemu.dtb \
		-accel $(QEMU_ACCEL) \
		-m 512 \
		-cpu cortex-a53 -M virt,highmem=off \
		-bios roms/u-boot-arm64-ramfb.bin \
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

tftp: dainboot/zig-cache/bin/BOOTAA64.rockpro64.efi dainkrnl/zig-cache/bin/dainkrnl.rockpro64
	tools/update-tftp

qemu: target/disk/EFI/BOOT/BOOTAA64.efi target/disk/dainkrnl
	$(QEMU_CMD) -s $$EXTRA_ARGS
	
dtb/qemu.dtb:
	$(QEMU_CMD) -machine dumpdtb=$@
	dtc $@ -o $@

OS_FILES=$(shell find dainkrnl -name zig-cache -prune -o -type f) $(shell find common -type f)
dainkrnl/zig-cache/bin/dainkrnl.%: $(OS_FILES)
	cd dainkrnl && zig build -Dboard=$*

target/disk/dainkrnl: dainkrnl/zig-cache/bin/dainkrnl.qemu
	mkdir -p $(@D)
	cp $< $@

DAINBOOT_FILES=$(shell find dainboot -name zig-cache -prune -o -type f -name \*.zig) $(shell find common -type f)
dainboot/zig-cache/bin/BOOTAA64.%.efi: $(DAINBOOT_FILES)
	cd dainboot && zig build -Dboard=$*

target/disk/EFI/BOOT/BOOTAA64.efi: dainboot/zig-cache/bin/BOOTAA64.qemu.efi
	mkdir -p $(@D)
	cp $< $@

CI_QEMU_ACCEL=tcg

ci: dainboot/zig-cache/bin/BOOTAA64.qemu.efi \
	dainboot/zig-cache/bin/BOOTAA64.rockpro64.efi \
	dainkrnl/zig-cache/bin/dainkrnl.qemu \
	dainkrnl/zig-cache/bin/dainkrnl.rockpro64 \
	target/disk/dainkrnl target/disk/EFI/BOOT/BOOTAA64.efi
	env CI_QEMU_ACCEL="$(CI_QEMU_ACCEL)" tools/ci-expect

clean:
	-rm -rf dtb/zig-cache dainkrnl/zig-cache dainboot/zig-cache target

%.dts:
	dtc -I dtb -O dts $*

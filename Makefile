.PHONY: qemu

ARCH =

ifndef ARCH
$(error ARCH should be arm64 or riscv64)
endif

ifeq ($(ARCH),arm64)
QEMU_BIN := qemu-system-aarch64
QEMU_BIOS := roms/u-boot-arm64-ramfb.bin
EFI_BOOTLOADER_NAME := BOOTAA64
else ifeq ($(ARCH),riscv64)
QEMU_BIN := qemu-system-riscv64
QEMU_BIOS := roms/u-boot-riscv64-ramfb.bin
EFI_BOOTLOADER_NAME := BOOTRISCV64
else
$(error ARCH should be arm64 or riscv64)
endif

QEMU_ACCEL := tcg
ifeq ($OS),Windows NT)
else
	UNAME_S := $(shell uname -s)
	ifeq ($(UNAME_S),Darwin)
		ifeq ($(ARCH),arm64)
			QEMU_ACCEL := hvf
		endif
	endif
endif

QEMU_CMD := $(QEMU_BIN) \
		-dtb dtb/qemu.dtb \
		-accel $(QEMU_ACCEL) \
		-m 512 \
		-cpu cortex-a53 -M virt,highmem=off \
		-bios $(QEMU_BIOS) \
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

qemu: target/disk/EFI/BOOT/$(EFI_BOOTLOADER_NAME).efi target/disk/dainkrnl
	$(QEMU_CMD) -s $$EXTRA_ARGS

ifeq ($(ARCH),arm64)
tftp: dainboot/zig-cache/bin/BOOTAA64.rockpro64.efi dainkrnl/zig-cache/bin/dainkrnl.rockpro64
	tools/update-tftp
endif

dtb/qemu.dtb:
	$(QEMU_CMD) -machine dumpdtb=$@
	dtc $@ -o $@

OS_FILES=$(shell find dainkrnl -name zig-cache -prune -o -type f) $(shell find common -type f)
dainkrnl/zig-cache/bin/dainkrnl.%: $(OS_FILES)
	cd dainkrnl && zig build -Dboard=$*

target/disk/dainkrnl: dainkrnl/zig-cache/bin/dainkrnl.qemu_$(ARCH)
	mkdir -p $(@D)
	cp $< $@

DAINBOOT_FILES=$(shell find dainboot -name zig-cache -prune -o -type f -name \*.zig) $(shell find common -type f)
dainboot/zig-cache/bin/$(EFI_BOOTLOADER_NAME).%.efi: $(DAINBOOT_FILES)
	cd dainboot && zig build -Dboard=$*

target/disk/EFI/BOOT/$(EFI_BOOTLOADER_NAME).efi: dainboot/zig-cache/bin/$(EFI_BOOTLOADER_NAME).qemu_$(ARCH).efi
	mkdir -p $(@D)
	cp $< $@

ci: dainboot/zig-cache/bin/BOOTAA64.qemu.efi \
	dainboot/zig-cache/bin/BOOTAA64.rockpro64.efi \
	dainkrnl/zig-cache/bin/dainkrnl.qemu \
	dainkrnl/zig-cache/bin/dainkrnl.rockpro64 \
	target/disk/dainkrnl target/disk/EFI/BOOT/BOOTAA64.efi
	tools/ci-expect

clean:
	-rm -rf dtb/zig-cache dainkrnl/zig-cache dainboot/zig-cache target

%.dts:
	dtc -I dtb -O dts $*

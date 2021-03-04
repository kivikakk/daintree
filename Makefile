.PHONY: qemu

ARCH =

ifndef ARCH
$(error ARCH should be arm64 or riscv64)
endif

ifeq ($(ARCH),arm64)
QEMU_BIN := qemu-system-aarch64
QEMU_ARGS := \
       -bios roms/u-boot-arm64-ramfb.bin \
       -cpu cortex-a53 -M virt,highmem=off \

QEMU_DTB_ARGS := -dtb dtb/qemu_$(ARCH).dtb
EFI_BOOTLOADER_NAME := BOOTAA64
else ifeq ($(ARCH),riscv64)
QEMU_BIN := qemu-system-riscv64
QEMU_ARGS := \
	-bios roms/u-boot-riscv64-ramfb.bin \
	-M virt \
	-device ich9-ahci,id=ahci -device ide-hd,drive=hd0 \

# riscv64 doesn't like loading a dtb at the moment.
# Fails -- possibly our fault!
# qemu-system-riscv64: FDT: Failed to create subnode /fw-cfg@10100000: FDT_ERR_EXISTS
QEMU_DTB_ARGS :=
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
		-accel $(QEMU_ACCEL) \
		-m 512 \
		$(QEMU_ARGS) \
		-serial stdio \
		-drive file=fat:rw:target/disk,format=raw,id=hd0 \
		-device virtio-net-device,netdev=net0 \
		-netdev user,id=net0 \
		-vga none \
		-device ramfb \
		-device usb-ehci \
		-device usb-kbd \
		-device usb-mouse \
		-usb \

qemu: target/disk/EFI/BOOT/$(EFI_BOOTLOADER_NAME).efi target/disk/dainkrnl
	$(QEMU_CMD) $(QEMU_DTB_ARGS) -s $$EXTRA_ARGS

ifeq ($(ARCH),arm64)
tftp: dainboot/zig-cache/bin/BOOTAA64.rockpro64.efi dainkrnl/zig-cache/bin/dainkrnl.rockpro64
	tools/update-tftp
endif

dtb/%.dtb:
	$(QEMU_CMD) -machine dumpdtb=$@
	dtc $@ -o $@

OS_FILES=$(shell find dainkrnl -name zig-cache -prune -o -type f) $(shell find common -type f)
dainkrnl/zig-cache/bin/dainkrnl.%: $(OS_FILES)
	cd dainkrnl && zig build -Dboard=$*

target/disk/dainkrnl: dainkrnl/zig-cache/bin/dainkrnl.qemu_$(ARCH)
	mkdir -p $(@D)
	cp $< $@

DAINBOOT_FILES=$(shell find dainboot -name zig-cache -prune -o -type f -name \*.zig) $(shell find common -type f) dainboot/elf_riscv64_efi.lds
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

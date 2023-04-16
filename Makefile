.PHONY: qemu clean

all: qemu

clean:
	-rm -rf dtb/zig-cache dtb/zig-out dainkrnl/zig-cache dainkrnl/zig-out dainboot/zig-cache dainboot/zig-out target

%.dts:
	dtc -I dtb -O dts $*

# Everything below needs ARCH.

ARCH =
QEMU_RAMFB = -device ramfb
QEMU_DTB_ARGS := -dtb dtb/src/qemu_$(ARCH).dtb

ifeq ($(ARCH),arm64)
QEMU_BIN := qemu-system-aarch64
QEMU_ARGS := \
	-bios roms/u-boot-arm64-ramfb.bin \
	-drive file=roms/ovmf_vars.fd,if=pflash,format=raw,index=1 \
	-cpu cortex-a53 -M virt,highmem=off \

EFI_BOOTLOADER_NAME := BOOTAA64
else ifeq ($(ARCH),riscv64)
QEMU_BIN := qemu-system-riscv64
QEMU_ARGS := \
	-bios roms/opensbi-u-boot-riscv64-ramfb.elf \
	-M virt \
	-device virtio-blk-device,drive=hd0 \

QEMU_RAMFB =

EFI_BOOTLOADER_NAME := BOOTRISCV64
else
$(error ARCH must be set to arm64 or riscv64)
endif

QEMU_ACCEL := tcg
ifeq ($OS),Windows NT)
else
	UNAME_S := $(shell uname -s)
	ifeq ($(UNAME_S),Darwin)
		ifeq ($(ARCH),arm64)
			QEMU_ACCEL := tcg
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
		$(QEMU_RAMFB) \
		-device usb-ehci \
		-device usb-kbd \
		-device usb-mouse \
		-usb \

qemu: target/disk/EFI/BOOT/$(EFI_BOOTLOADER_NAME).efi target/disk/dainkrnl.$(ARCH)
	$(QEMU_CMD) $(QEMU_DTB_ARGS) -s $$EXTRA_ARGS

dtb/src/%.dtb:
	$(QEMU_CMD) -machine dumpdtb=$@
	dtc $@ -o $@

ifeq ($(ARCH),arm64)
tftp: dainboot/zig-out/bin/BOOTAA64.rockpro64.efi dainkrnl/zig-out/bin/dainkrnl.rockpro64
	tools/update-tftp
endif

OS_FILES=$(shell find dainkrnl -name zig-out -prune -o -type f) $(shell find common -type f)
dainkrnl/zig-out/bin/dainkrnl.%: $(OS_FILES)
	cd dainkrnl && zig build -Dboard=$*

target/disk/dainkrnl.$(ARCH): dainkrnl/zig-out/bin/dainkrnl.qemu_$(ARCH)
	mkdir -p $(@D)
	cp $< $@

DAINBOOT_FILES=$(shell find dainboot -name zig-cache -prune -o -type f -name \*.zig) $(shell find common -type f) dainboot/elf_riscv64_efi.lds dainboot/src/crt0-efi-riscv64.S
dainboot/zig-out/bin/$(EFI_BOOTLOADER_NAME).%.efi: $(DAINBOOT_FILES)
	cd dainboot && zig build -Dboard=$*

target/disk/EFI/BOOT/$(EFI_BOOTLOADER_NAME).efi: dainboot/zig-out/bin/$(EFI_BOOTLOADER_NAME).qemu_$(ARCH).efi
	mkdir -p $(@D)
	cp $< $@

ci: target/disk/dainkrnl.$(ARCH) target/disk/EFI/BOOT/$(EFI_BOOTLOADER_NAME).efi
	tools/ci-expect-$(ARCH)

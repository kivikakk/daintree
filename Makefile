.PHONY: qemu mk-ovmf-vars mk-disk

qemu:
	qemu-system-aarch64 \
		-accel hvf \
		-m 512 \
		-cpu cortex-a57 -M virt,highmem=off \
		-drive file=/opt/homebrew/share/qemu/edk2-aarch64-code.fd,if=pflash,format=raw,readonly=on \
		-drive file=ovmf_vars.fd,if=pflash,format=raw \
		-serial telnet::4444,server,nowait \
		-drive if=none,file=disk.qcow2,format=qcow2,id=hd0 \
		-device virtio-blk-device,drive=hd0,serial="dummyserial" \
		-device virtio-net-device,netdev=net0 \
		-netdev user,id=net0 \
		-vga none \
		-device ramfb \
		-device usb-ehci \
		-device usb-kbd \
		-device usb-mouse \
		-usb \
		-monitor stdio

mk-ovmf-vars:
	dd if=/dev/zero conv=sync bs=1m count=64 of=ovmf_vars.fd

mk-disk:
	qemu-img create -f qcow2 disk.qcow2 128M

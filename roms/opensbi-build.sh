#!/bin/sh

make CROSS_COMPILE=riscv64-linux-gnu- PLATFORM=generic FW_PAYLOAD_PATH=$HOME/Code/u-boot/u-boot.bin

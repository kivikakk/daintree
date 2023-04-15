#!/bin/sh

export CROSS_COMPILE=riscv64-linux-gnu-

gmake qemu-riscv64_smode_defconfig
gmake -j8

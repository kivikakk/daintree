#!/bin/sh

export CROSS_COMPILE=aarch64-linux-gnu-

gmake qemu_arm64_defconfig
gmake -j8

# NanoPC T6 Hardware Support

WIP

## Linux kernel

The NanoPC T6 can boot a mainline Linux kernel, but will lack video support.

There is a rockchip fork of the mainline kernel, which in turn has several forks for supporting various projects.

Documentation used for NixOS/Dogebox support: 

 - https://nixos.wiki/wiki/Linux_kernel  -  Started here, using the section 'Building a kernel from a custom source', ended up needing a 'linuxManualConfig' call rather than a 'buildLinux' call so we could supply a full .config

 - https://github.com/choushunn/awesome-RK3588
 - https://github.com/ryan4yin/nixos-rk3588  -  Another project supporting NixOS on other rk3588 based SBCs


 - https://github.com/friendlyarm/sd-fuse_rk3588  -  FriendlyElect's image building tool
 - https://github.com/friendlyarm/kernel-rockchip/blob/nanopi6-v6.1.y/arch/arm64/configs/nanopi6_linux_defconfig  -  The kernel .config file the above tool uses


 - https://github.com/armbian/linux-rockchip  -  Rockchip linux kernel forks used by nixos-rk3588
 - https://github.com/orangepi-xunlong/linux-orangepi


### .config modifications needed

  - CONFIG_DMIID=y
  - CONFIG_VIDEO_ROCKCHIP_CIF=n
  - CONFIG_MALI_MIDGARD=n
  - CONFIG_VENDOR_FRIENDLYELEC=y
  - 'Zero memory on allocation'

## Device peripheral firmware

https://github.com/friendlyarm/sd-fuse_rk3588.git
prebuilt/firmware/install.sh

## OP-TEE

Dogebox's NanoPC-T6 OP-TEE build enables Rockchip secure boot PTA support
(`CFG_RK_SECURE_BOOT=y`) so secure boot fuse management can be driven through
OP-TEE.

The Rockchip secure boot feature here is implemented as an OP-TEE pseudo TA
(`core/pta/rockchip/rk_secure_boot.c` upstream), with command handlers for:

- `PTA_RK_SECURE_BOOT_GET_INFO`
- `PTA_RK_SECURE_BOOT_BURN_HASH`
- `PTA_RK_SECURE_BOOT_LOCKDOWN_DEVICE`

Involvement in Dogebox is:

1. NanoPC-T6 boots with BL31 + OP-TEE (`tee.bin`) + U-Boot.
2. `CFG_RK_SECURE_BOOT=y` compiles and registers `rk_secure_boot.pta` in OP-TEE.
3. A normal-world client (bootloader or userspace TEEC client) opens the PTA
   UUID and invokes the commands above to read/burn/lock secure-boot OTP state.

So enabling the PTA in Dogebox exposes the secure-world API needed for secure
boot provisioning; it is not invoked automatically unless a client calls it.

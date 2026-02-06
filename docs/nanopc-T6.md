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

## Reset Button Support

The NanoPC-T6 has a physical reset button that is connected to GPIO1_PC0. This button is configured in the device tree patch (`rk3588-nanopc-t6.dtsi.patch`) as follows:

- **GPIO Pin**: GPIO1_PC0 (Bank 1, Port C, Pin 0)
- **Key Code**: KEY_POWER
- **Active Level**: LOW (button press pulls the pin low)
- **Debounce**: 50ms
- **Wakeup Source**: Yes (can wake the system from sleep)

The kernel driver for GPIO keys (`CONFIG_KEYBOARD_GPIO=y`) is enabled in the defconfig, so the button should function as a power button when pressed.

**Note**: The GPIO pin assignment was verified from the FriendlyARM kernel source (`nanopi6-v6.1.y` branch, `rk3588-nanopi6-rev02.dts`). This is the device tree variant that includes the button configuration. The standard NanoPC-T6 (rev01) in the FriendlyARM kernel did not have this button configured, which is why it didn't work in their fork until later revisions added it.

## Device peripheral firmware

https://github.com/friendlyarm/sd-fuse_rk3588.git
prebuilt/firmware/install.sh

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

The NanoPC-T6 has a physical reset/power button that is **connected to the RK806 PMIC's pwrkey input**, not to a GPIO pin. This button is configured in the device tree patch (`rk3588-nanopc-t6.dtsi.patch`) as follows:

- **Connection**: RK806 PMIC pwrkey input
- **Driver**: `rk805-pwrkey` (automatically instantiated by MFD driver)
- **Key Code**: KEY_POWER
- **Kernel Config**: 
  - `CONFIG_INPUT_RK805_PWRKEY=y` 
  - `CONFIG_MFD_RK806_SPI=y` (FriendlyARM kernel variant)

The button works by triggering interrupts (PWRON_FALL and PWRON_RISE) on the RK806 PMIC, which are handled by the kernel's rk805-pwrkey driver. This is the same mechanism used in U-Boot and the FriendlyARM kernel fork.

### Device Tree Configuration

In the PMIC node (`&spi2 > pmic@0`), the pwrkey node is enabled after the DVS pinctrl definitions and before the `regulators` block:

```dts
rk806_dvs3_null: dvs3-null-pins {
    pins = "gpio_pwrctrl3";
    function = "pin_fun0";
};

pwrkey {
    status = "okay";
};

regulators {
    ...
}
```

This enables the MFD driver to instantiate the power key device, which registers as a standard input device generating KEY_POWER events.

**Important Note**: The pwrkey node placement matches the Rockchip kernel device tree structure, which differs from mainline Linux. It should come after the pinctrl definitions and before the regulators block in the Rockchip kernel.

**Kernel Variant**: This system uses the FriendlyARM-based Rockchip kernel (`kernel_linux_latest_rockchip_stable`), which uses `rk806-core.c` MFD driver instead of mainline's `rk8xx-core.c`. The FriendlyARM driver checks for the pwrkey device tree node and requires it to be explicitly enabled with `status = "okay"`.

**Previous Incorrect Approach**: Earlier attempts tried to configure the button as a GPIO key on GPIO1_PC0, but this was incorrect. The button is physically wired to the PMIC, not to a regular GPIO pin.

## Device peripheral firmware

https://github.com/friendlyarm/sd-fuse_rk3588.git
prebuilt/firmware/install.sh

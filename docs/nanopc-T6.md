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

The NanoPC-T6 has a physical power/reset button connected to the **RK806 PMIC's pwrkey input** (not to a GPIO pin).

### How It Works

1. **Hardware**: Button press triggers the RK806 PMIC's PWRON interrupt lines (PWRON_FALL on press, PWRON_RISE on release)
2. **Kernel**: The mainline `rk8xx-core.c` MFD driver automatically registers an `rk805-pwrkey` platform device for RK806 PMICs — no device tree `pwrkey` node is needed
3. **Input**: The `rk805-pwrkey` driver generates `KEY_POWER` input events
4. **Userspace**: `systemd-logind` handles `KEY_POWER` events according to `HandlePowerKey` configuration

### Kernel Configuration

The following kernel config options are required (added via `structuredExtraConfig` since nabam's kernel doesn't include them):

- `CONFIG_MFD_RK8XX_SPI=y` — RK806 PMIC MFD driver via SPI bus
- `CONFIG_INPUT_RK805_PWRKEY=y` — Power key input driver for RK8XX PMICs
- `CONFIG_PINCTRL_RK805=y` — RK8XX family pinctrl driver

These are **mainline kernel** config names. The FriendlyARM vendor kernel (v6.1.y) uses different names (`CONFIG_MFD_RK806_SPI`, etc.) — do not confuse them.

### systemd-logind Configuration

The power key behavior is configured in `base.nix`:

- **Short press**: `HandlePowerKey=reboot` — triggers a clean reboot
- **Long press**: `HandlePowerKeyLongPress=poweroff` — triggers a clean shutdown

Without explicit configuration, NixOS defaults `HandlePowerKey` to `poweroff`, which on a headless device silently shuts down instead of rebooting.

### Important: Mainline vs FriendlyARM Vendor Kernel

This system uses `nabam/nixos-rockchip`'s `kernel_linux_latest_rockchip_stable`, which is the **mainline Linux kernel** with Rockchip-specific config options. It is NOT the FriendlyARM vendor kernel (v6.1.y).

Key differences for pwrkey:
- **Mainline kernel**: `rk8xx-core.c` unconditionally creates pwrkey MFD cell for RK806 — no DT node needed
- **FriendlyARM kernel**: `rk806-core.c` requires an explicit `pwrkey { status = "okay"; }` DT node

The device tree patch should NOT include a `pwrkey` node — it would be ignored by the mainline driver and could cause DT validation warnings.

### Previous Incorrect Approach

Earlier attempts tried:
1. Configuring the button as a GPIO key (GPIO1_PC0) — incorrect, button is wired to PMIC
2. Adding `pwrkey { status = "okay"; }` DT node — only works with FriendlyARM vendor kernel, not mainline

## Device peripheral firmware

https://github.com/friendlyarm/sd-fuse_rk3588.git
prebuilt/firmware/install.sh

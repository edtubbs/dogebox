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

## Buttons

The NanoPC-T6 has **three distinct physical buttons** with different hardware connections and behaviors:

### 1. Power Button (PWRON)

- **Hardware**: Connected to the RK806 PMIC's **PWRON** input pin
- **Mechanism**: PMIC-level power control with interrupt notification to kernel
- **Kernel driver**: `rk805-pwrkey` (auto-created by mainline `rk8xx-core.c` MFD driver — no device tree `pwrkey` node needed)
- **Input event**: `KEY_POWER`
- **Behavior**: Handled by `systemd-logind` (`HandlePowerKey`). NixOS default is `poweroff`.

#### Kernel Configuration

The following kernel config options are required (added via `structuredExtraConfig` since nabam's kernel doesn't include them):

- `CONFIG_MFD_RK8XX_SPI=y` — RK806 PMIC MFD driver via SPI bus
- `CONFIG_INPUT_RK805_PWRKEY=y` — Power key input driver for RK8XX PMICs
- `CONFIG_PINCTRL_RK805=y` — RK8XX family pinctrl driver

These are **mainline kernel** config names. The FriendlyARM vendor kernel (v6.1.y) uses different names (`CONFIG_MFD_RK806_SPI`, etc.) — do not confuse them.

### 2. Reset Button (RESETB)

- **Hardware**: Connected to the RK806 PMIC's **RESETB** input pin
- **Mechanism**: Pure hardware reset — asserts RESETB low, which triggers the PMIC's reset function. **Bypasses the kernel entirely** (no software event, no clean shutdown)
- **Kernel driver**: None — handled at PMIC hardware level
- **Input event**: None
- **Behavior**: Configured by the `rockchip,reset-mode` device tree property on the RK806 PMIC node:
  - Mode 0: Restart PMU (full power cycle, regulators briefly interrupted)
  - Mode 1: Reset all power off registers, force state to ACTIVE mode
  - Mode 2: Same as mode 1, also pulls RESETB pin down for 5ms

The device tree patch sets `rockchip,reset-mode = <1>` to match the FriendlyARM vendor kernel behavior (`pmic-reset-func = <1>`). Without this property, the PMIC uses its hardware default. The mainline kernel's `rk8xx-core.c` reads this property during probe and writes it to `RK806_SYS_CFG3`.

### 3. Mask ROM Button (SARADC)

- **Hardware**: Connected to **SARADC channel 0** via voltage divider
- **Mechanism**: ADC-based key detection (reads analog voltage level)
- **Kernel driver**: `adc-keys` (already in mainline DTS as `adc-keys-0` node)
- **Input event**: `KEY_SETUP` (Mask Rom)
- **Behavior**: Used for entering Mask ROM/recovery mode when held during power-on. In U-Boot, detected via `CONFIG_BUTTON_ADC`.

### Important: Mainline vs FriendlyARM Vendor Kernel

This system uses `nabam/nixos-rockchip`'s `kernel_linux_latest_rockchip_stable`, which is the **mainline Linux kernel** with Rockchip-specific config options. It is NOT the FriendlyARM vendor kernel (v6.1.y).

Key differences:
- **Mainline kernel**: `rk8xx-core.c` unconditionally creates pwrkey MFD cell for RK806. Reset mode configured via `rockchip,reset-mode` DT property.
- **FriendlyARM kernel**: `rk806-core.c` requires an explicit `pwrkey { status = "okay"; }` DT node. Reset mode configured via `pmic-reset-func` DT property.

### Previous Incorrect Approaches

Earlier attempts tried:
1. Configuring the reset button as a GPIO key (GPIO1_PC0) — incorrect, reset is wired to PMIC RESETB
2. Adding `pwrkey { status = "okay"; }` DT node — only works with FriendlyARM vendor kernel
3. Treating the power button and reset button as the same button — they are separate hardware
4. Configuring `HandlePowerKey=reboot` in systemd-logind — this changes the power button behavior, not the reset button which is hardware-only

## Device peripheral firmware

https://github.com/friendlyarm/sd-fuse_rk3588.git
prebuilt/firmware/install.sh

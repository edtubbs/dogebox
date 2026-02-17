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

The following kernel config options are required (added via `structuredExtraConfig`):

- `CONFIG_MFD_RK8XX_SPI=y` — RK806 PMIC MFD driver via SPI bus
- `CONFIG_INPUT_RK805_PWRKEY=y` — Power key input driver for RK8XX PMICs
- `CONFIG_PINCTRL_RK805=y` — RK8XX family pinctrl driver

These are **mainline kernel** config names. The FriendlyARM vendor kernel (v6.1.y) uses different names (`CONFIG_MFD_RK806_SPI`, etc.) — do not confuse them.

### 2. Reset Button (RESETB)

- **Hardware**: Connected to the RK806 PMIC's **RESETB** input pin
- **Mechanism**: Pure hardware reset — asserts RESETB low, which triggers the PMIC's reset function. **Bypasses the kernel entirely** (no software event, no clean shutdown)
- **Kernel driver**: None — handled at PMIC hardware level
- **Input event**: None
- **Behavior**: Configured by `RST_FUN` bits [7:6] in the RK806's `SYS_CFG3` register (0x72). The mainline kernel DT binding (`rockchip,reset-mode`) and FriendlyARM vendor DT property (`pmic-reset-func`) both map to this register:
  - Mode 0: **Restart PMU** — full power cycle of all regulators
  - Mode 1: Reset all power-off registers, force state to ACTIVE mode (FriendlyARM default)
  - Mode 2: Same as mode 1, also pulls RESETB pin low for 5ms (resets SoC via CHIP_RESETB)

**Current approach** (two-part fix):

1. **Kernel patch** (`rk806-disable-slave-restart.patch`): The mainline `rk8xx-core.c` MFD driver unconditionally enables `SLAVE_RESTART_FUN` (SYS_CFG3 bit[1]) during probe for multi-PMIC setups where a master can restart slave PMICs via the RESETB pin. On the NanoPC-T6 (single PMIC), this is unnecessary and may interfere with RESETB button input handling. The kernel patch changes the `rk806_pre_init_reg[]` entry from `RK806_SLAVE_RESTART_FUN_EN` to `RK806_SLAVE_RESTART_FUN_OFF`.

2. **DT property** (`rockchip,reset-mode = <2>`): Mode 2 resets PMIC registers, forces ACTIVE state, AND explicitly pulls the RESETB output low for 5ms. This ensures the SoC's reset input (CHIP_RESETB_N) sees the reset signal. Mode 0 (PMU restart) might not reliably reset the SoC if bypass capacitors hold power rails above the POR threshold. Mode 2 avoids this by using the dedicated reset signal path.

The DTS patch also carries the OP-TEE `firmware`/`reserved-memory` nodes, which are required for this image and should not be removed.

FriendlyARM's vendor kernel uses `pmic-reset-func = <1>` and their vendor PMIC driver (`rk806-core.c`) handles it differently from mainline.

### 3. Mask ROM Button (SARADC)

- **Hardware**: Connected to **SARADC channel 0** via voltage divider
- **Mechanism**: ADC-based key detection (reads analog voltage level)
- **Kernel driver**: `adc-keys` (already in mainline DTS as `adc-keys-0` node)
- **Input event**: `KEY_SETUP` (Mask Rom)
- **Behavior**: Used for entering Mask ROM/recovery mode when held during power-on. In U-Boot, detected via `CONFIG_BUTTON_ADC`.

### Important: Mainline vs FriendlyARM Vendor Kernel

This system prefers `nabam/nixos-rockchip`'s `kernel_linux_latest_rockchip_unstable` (Rockchip-tuned mainline) and falls back to nixpkgs `linuxPackages_latest` if that input is unavailable. It is NOT the FriendlyARM vendor kernel (v6.1.y).

Key differences:
- **Mainline kernel**: `rk8xx-core.c` unconditionally creates pwrkey MFD cell for RK806. Unconditionally enables `SLAVE_RESTART_FUN` in pre_init_reg. Reset mode configured via `rockchip,reset-mode` DT property.
- **FriendlyARM kernel**: `rk806-core.c` requires an explicit `pwrkey { status = "okay"; }` DT node. Does NOT enable `SLAVE_RESTART_FUN`. Reset mode configured via `pmic-reset-func` DT property.

### Previous Incorrect Approaches

Earlier attempts tried:
1. Configuring the reset button as a GPIO key (GPIO1_PC0) — incorrect, reset is wired to PMIC RESETB
2. Adding `pwrkey { status = "okay"; }` DT node — only works with FriendlyARM vendor kernel
3. Treating the power button and reset button as the same button — they are separate hardware
4. Configuring `HandlePowerKey=reboot` in systemd-logind — this changes the power button behavior, not the reset button which is hardware-only
5. Setting `rockchip,reset-mode = <1>` — was never actually tested due to malformed patch (build failed)
6. Setting `rockchip,reset-mode = <0>` — mode 0 (restart PMU) tested but didn't work; SoC may not reset if caps hold voltage
7. Removing `rockchip,reset-mode` entirely — tested but didn't work; letting U-Boot config persist wasn't enough because the MFD driver's `pre_init_reg` still modifies SYS_CFG3 (enables SLAVE_RESTART_FUN)
8. **Current fix**: Disable SLAVE_RESTART_FUN via kernel patch + set mode 2 via DT for explicit RESETB output assertion

## Device peripheral firmware

https://github.com/friendlyarm/sd-fuse_rk3588.git
prebuilt/firmware/install.sh

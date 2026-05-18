{
  inputs,
  pkgs,
  lib,
  config,
  nanopc-t6-rk3588-firmware,
  ...
}:

{
  nixpkgs.overlays = lib.mkAfter [
    (final: super: {
      makeModulesClosure = x: super.makeModulesClosure (x // { allowMissing = true; });

      optee-os-rockchip-rk3588 = final.buildOptee {
        platform = "rockchip-rk3588";
        extraMakeFlags = [
          "CFG_TEE_CORE_LOG_LEVEL=0"
          "CFG_ATTESTATION_PTA=y"
          "CFG_ATTESTATION_PTA_KEY_SIZE=1024"
          "CFG_WITH_USER_TA=y"
          "CFG_WITH_SOFTWARE_PRNG=n"
        ];
      };

      armTrustedFirmwareRK3588 = super.armTrustedFirmwareRK3588.overrideAttrs (old: {
        makeFlags = old.makeFlags ++ [ "SPD=opteed" "LOG_LEVEL=40" "bl31" ];
      });

      uBootNanoPCT6 = super.buildUBoot {
        defconfig = "nanopc-t6-rk3588_defconfig";
        extraMeta.platforms = [ "aarch64-linux" ];
        extraMakeFlags = [
          "BL31=${pkgs.armTrustedFirmwareRK3588}/bl31.elf"
          "ROCKCHIP_TPL=${pkgs.rkbin.TPL_RK3588}"
          "TEE=${final.optee-os-rockchip-rk3588}/tee.bin"
        ];
        filesToInstall = [
          "u-boot.itb"
          "idbloader.img"
        ];
      };
    })
  ];

  # Show everything in the tty console instead of serial.
  # Ideally we'd use `ttyFIQ0` which is a special debug serial on the rk3588,
  # however, the mainline kernel did not seem to have this implemented as of
  # 2025-12-08 so we're forced to use a different console.
  boot.kernelParams = [ "console=tty1" ];

  # Use the extlinux boot loader. (NixOS wants to enable GRUB by default)
  boot.loader.grub.enable = false;
  # Enables the generation of /boot/extlinux/extlinux.conf
  boot.loader.generic-extlinux-compatible.enable = true;
  boot.loader.timeout = 1;

  boot.kernelPackages =
    inputs.rockchip.legacyPackages.aarch64-linux.kernel_linux_latest_rockchip_stable;

  boot.kernelPatches = [
    {
      name = "rk3588-nanopc-t6.dtsi.patch";
      patch = ./rk3588-nanopc-t6.dtsi.patch;
    }
  ];

  boot.initrd.availableKernelModules = [
    "nvme"
    "usbhid"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [
    "rtw88_8822ce"
    "rtw88_pci"
    "rtw88_core"
  ];

  boot.extraModulePackages =
    let
      rtw88 = config.boot.kernelPackages.callPackage ./rtw88 { };
    in
    [ rtw88 ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  environment.systemPackages = with pkgs; [
    avahi
    cloud-utils
    parted
    screen
    wpa_supplicant
    uBootNanoPCT6
  ];

  environment.etc."uboot".source = pkgs.uBootNanoPCT6;

  # Initial hostName for the box to respond to dogebox.local for first boot and installation steps.
  # Will be replaced by dogeboxd configuration
  networking.hostName = lib.mkDefault "dogebox";
  services.avahi = {
    nssmdns4 = true;
    nssmdns6 = true;

    enable = true;
    reflector = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
      userServices = true;
    };
  };

  # Wi-Fi behaviour is split into two phases driven by which medium the
  # rootfs was booted from. The AP (`Dogebox` SSID on the `ap0` vif) comes
  # up unconditionally on every boot — it is the user's only guaranteed
  # path to dpanel in both phases — and STA on `wlan0` is layered on top:
  #
  #   * First boot (SD card, installer phase): AP only. The SD→eMMC flow
  #     does not need upstream internet — it just needs the user to reach
  #     dpanel and trigger the install. STA is suppressed via
  #     `/run/dogebox/sta-disabled` so a missing `/etc/dogebox/wifi.env`
  #     (which the GUI hasn't written yet) cannot hang
  #     `wpa_supplicant-wlan0.service` and block the AP from coming up.
  #
  #   * Second boot (eMMC, runtime phase): AP comes up immediately so the
  #     user can connect to `Dogebox` and reach dpanel even before any
  #     upstream credentials exist. dogeboxd uses `iw dev wlan0 scan` to
  #     enumerate nearby SSIDs (wlan0 is admin-up via
  #     `dogebox-ap0-vif.service`), the user picks one, dpanel writes
  #     `/etc/dogebox/wifi.env`, and `wpa_supplicant-wlan0.service` then
  #     activates STA on wlan0 — giving STA+AP concurrency with no reboot.
  #
  # The same image is written to eMMC, so the discriminator is runtime, not
  # build-time. NetworkManager / iwd are intentionally NOT used — they
  # conflict with `create_ap` on this rtw88 radio.
  networking.wireless.iwd.enable = false;
  networking.networkmanager.enable = false;

  # AP for initial setup — SSID/passphrase are intentionally hardcoded so the
  # user has a known, stable network to reach the dpanel on first boot.
  # WIFI_IFACE is the dedicated AP vif (`ap0`) created by
  # `dogebox-ap0-vif.service` below; INTERNET_IFACE remains `wlan0` so that
  # once STA associates on the eMMC boot, AP clients get NATed upstream.
  services.create_ap = {
    enable = lib.mkDefault true;
    settings = {
      WIFI_IFACE = "ap0";
      INTERNET_IFACE = "wlan0";
      SHARE_METHOD = "nat";
      FREQ_BAND = "2.4";
      SSID = "Dogebox";
      PASSPHRASE = "SuchPass";
    };
  };

  # Upstream Wi-Fi (STA) credentials are provided via a secrets file that
  # lives outside the Nix store, so the SSID/PSK the dogebox connects to for
  # internet access can be set before setup runs without rebuilding the image.
  #
  # The file must define (values are interpreted literally — quotes are part
  # of the value, so the SSID and passphrase must themselves be quoted as
  # wpa_supplicant expects):
  #   UPSTREAM_SSID="MyNetworkName"
  #   UPSTREAM_PSK="mypassphrase"
  # It should be owned by root with mode 0600 to avoid leaking the PSK.
  #
  # wpa_supplicant's `ext:` password backend resolves these references at
  # start-up, so the SSID/PSK never end up in the Nix store. The network is
  # declared via `extraConfig` (rather than `networking.wireless.networks`)
  # because the module uses the attribute name as the literal SSID and
  # provides no way to externalise it — `ext:` substitution only applies to
  # field values. wlan0 takes whatever IP the upstream network's DHCP server
  # hands out (default behaviour for `networking.wireless` — no static
  # address is configured here).
  #
  # The unit generated by this module is then constrained at runtime by the
  # `wpa_supplicant-wlan0` override below so it only runs on the eMMC boot,
  # and only once the GUI has written the secrets file.
  networking.wireless.enable = true;
  networking.wireless.interfaces = [ "wlan0" ];
  networking.wireless.secretsFile = "/etc/dogebox/wifi.env";
  networking.wireless.extraConfig = ''
    network={
      ssid=ext:UPSTREAM_SSID
      psk=ext:UPSTREAM_PSK
      key_mgmt=WPA-PSK
    }
  '';

  # Boot-mode detector. Runs early (before any wifi unit) and figures out
  # whether the rootfs came up off SD or eMMC, so the rest of the units can
  # branch on a simple file flag instead of trying to infer it themselves.
  #
  # On the NanoPC-T6, eMMC is `mmcblk0` and the SD slot is `mmcblk1` — that
  # naming is fixed by the rk3588 DTS and survives reboots. We resolve the
  # rootfs source the same way `resizerootfs` already does, then write:
  #   /run/dogebox/boot-mode      = "installer" | "runtime"
  #   /run/dogebox/sta-disabled   (only on installer boot)
  systemd.services.dogebox-boot-mode = {
    description = "Detect whether the rootfs booted from SD (installer) or eMMC (runtime)";
    wantedBy = [ "sysinit.target" ];
    before = [
      "network-pre.target"
      "wpa_supplicant-wlan0.service"
      "create_ap.service"
      "dogebox-ap0-vif.service"
    ];
    unitConfig = {
      DefaultDependencies = false;
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = with pkgs; [
      coreutils
      util-linux
    ];
    script = ''
      set -eu
      mkdir -p /run/dogebox

      ROOT_PART=$(basename "$(findmnt -c -n -o SOURCE /)")
      ROOT_DISK=$(basename "$(readlink -f "/sys/class/block/$ROOT_PART/..")")

      # rk3588: mmcblk0 = eMMC, mmcblk1 = SD slot.
      case "$ROOT_DISK" in
        mmcblk0*)
          echo "runtime" > /run/dogebox/boot-mode
          rm -f /run/dogebox/sta-disabled
          ;;
        *)
          echo "installer" > /run/dogebox/boot-mode
          : > /run/dogebox/sta-disabled
          ;;
      esac
    '';
  };

  # Create the dedicated AP virtual interface (`ap0`) on the wlan0 radio so
  # `create_ap` can run AP mode without fighting wpa_supplicant for the
  # underlying interface. Idempotent — `iw` exits non-zero if `ap0` already
  # exists, so we guard with a presence check.
  #
  # We also admin-up wlan0 here. The radio is needed admin-up for two
  # reasons that are independent of wpa_supplicant being active:
  #   1. On the eMMC boot, the GUI needs to scan for upstream SSIDs via
  #      `iw dev wlan0 scan` *before* wifi credentials exist, and `iw scan`
  #      requires the parent interface to be UP.
  #   2. ap0 is a vif on top of wlan0; some drivers (rtw88 included) are
  #      happier if the parent is admin-up before AP mode starts on the vif.
  systemd.services.dogebox-ap0-vif = {
    description = "Create AP virtual interface (ap0) on the wlan0 radio";
    wantedBy = [ "create_ap.service" ];
    after = [
      "dogebox-boot-mode.service"
      "sys-subsystem-net-devices-wlan0.device"
    ];
    before = [ "create_ap.service" ];
    wants = [ "sys-subsystem-net-devices-wlan0.device" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = with pkgs; [
      iw
      iproute2
    ];
    script = ''
      set -eu
      ip link set wlan0 up
      if ! ip link show ap0 >/dev/null 2>&1; then
        iw dev wlan0 interface add ap0 type __ap
      fi
      # Leave ap0 down — create_ap brings it up with the right config
      # (SSID, hostapd, dnsmasq) immediately after this oneshot completes.
    '';
  };

  # Make create_ap tolerant of an absent radio so a missing/failed wlan0
  # cannot wedge the unit in `activating`. The radio is brought up by the
  # rtw88 module either way; this just relaxes the dependency type.
  systemd.services.create_ap = {
    wants = [ "sys-subsystem-net-devices-wlan0.device" ];
    after = [
      "dogebox-ap0-vif.service"
      "sys-subsystem-net-devices-wlan0.device"
    ];
  };

  # Constrain the wpa_supplicant unit generated by `networking.wireless` so
  # it stays inactive on the installer boot (when `/run/dogebox/sta-disabled`
  # exists) and stays inactive on eMMC until the GUI writes the secrets file.
  # `ConditionPathExists` is ANDed across entries, and a failing condition
  # is a no-op for downstream units (it does not propagate failure).
  systemd.services."wpa_supplicant-wlan0" = {
    unitConfig = {
      # ! = required-to-be-absent. The other path is required-to-be-present.
      ConditionPathExists = [
        "!/run/dogebox/sta-disabled"
        "/etc/dogebox/wifi.env"
      ];
    };
    # Don't pin the unit to the wlan0 device — the upstream module uses
    # BindsTo, which forces the unit to stop/start in lockstep with the
    # interface and was the source of the boot-blocking job. `Wants` lets
    # systemd start the unit when the device shows up without coupling
    # their lifecycles.
    bindsTo = lib.mkForce [ ];
    wants = [ "sys-subsystem-net-devices-wlan0.device" ];
    after = [
      "dogebox-boot-mode.service"
      "sys-subsystem-net-devices-wlan0.device"
    ];
    # If the GUI rewrites the creds (e.g. user picked a new network), let
    # the unit recover on its own rather than requiring a manual restart.
    serviceConfig = {
      Restart = lib.mkForce "on-failure";
      RestartSec = "5s";
    };
  };

  # Allow AP clients to obtain an IP (DHCP, port 67) and resolve names
  # (DNS, port 53) via the dnsmasq instance create_ap brings up.
  networking.firewall.allowedUDPPorts = [ 53 67 ];

  systemd.services.resizerootfs = {
    description = "Expands root filesystem of boot device on first boot";
    unitConfig = {
      type = "oneshot";
      after = [ "sysinit.target" ];
    };
    script = ''
      if [ ! -e /etc/fs.resized ];
        then
          echo "Expanding root filesystem . . ."
          PATH=$PATH:/run/current-system/sw/bin/
          ROOT_PART=$(basename "$(findmnt -c -n -o SOURCE /)")
          ROOT_PART_NUMBER=$(cat /sys/class/block/$ROOT_PART/partition)
          ROOT_DISK=$(basename "$(readlink -f "/sys/class/block/$ROOT_PART/..")")
          growpart /dev/"$ROOT_DISK" "$ROOT_PART_NUMBER" || if [ $? == 2 ]; then echo "Error with growpart"; exit 2; fi
          partprobe
          resize2fs /dev/"$ROOT_PART"
          touch /etc/fs.resized
        fi
    '';
    wantedBy = [
      "basic.target"
      "runOnceOnFirstBoot.service"
    ];
  };

  services.pcscd.enable = true;
  services.udev.packages = [ pkgs.yubikey-personalization ];
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="usb", GROUP="69", MODE="0660"
    ACTION=="add", KERNEL=="hidraw*", GROUP="69", MODE="0660"
  '';

  system.activationScripts.rk3588-firmware = ''
    mkdir -p /etc/firmware
    mkdir -p /lib/firmware
    mkdir -p /system

    for i in /etc/firmware /lib/firmware /system;
    do
      [ -L $i ] && echo "Removing old symlink $i" && rm $i
      [ -e $i ] && echo "Moving $i out of the way" && mv $i $i.`date -I`
    done
    echo "Adding new firmware symlinks"
    ln -sf ${nanopc-t6-rk3588-firmware}/etc/firmware/ /etc/firmware
    ln -sf ${nanopc-t6-rk3588-firmware}/lib/firmware/ /lib/firmware
    ln -sf ${nanopc-t6-rk3588-firmware}/system/ /system
  '';
}

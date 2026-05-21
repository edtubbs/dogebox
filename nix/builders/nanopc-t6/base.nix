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

  # AP for initial setup on the `Dogebox` SSID. STA credential management
  # is handled by dogeboxd at runtime; this image only needs to bring the
  # AP up so the user can reach dpanel.
  #
  # `iwd` is disabled here — it conflicts with `create_ap` on this rtw88
  # radio. `mkDefault` so dogeboxd's STA `network.nix` (which sets
  # `iwd.enable = true;` and force-disables `create_ap`) cleanly overrides
  # at normal priority without a `conflicting definition values` abort.
  # `FREQ_BAND = "2.4"` is required for AP+STA concurrency on the same radio.
  networking.wireless.iwd.enable = lib.mkDefault false;

  # Pin the rtw88 radio to the legacy name `wlan0`. Without this, systemd's
  # predictable interface naming renames it to something like `wlP3p49s0`,
  # which breaks the AP/STA flow that references `wlan0` by name
  # (`INTERNET_IFACE`, dogeboxd STA management, etc.).
  # `.link` files are processed by udev in early boot, before any service
  # that depends on the wlan0 device unit is started.
  systemd.network.links."10-wlan0" = {
    matchConfig.Driver = "rtw88_8822ce";
    linkConfig.Name = "wlan0";
  };

  # `create_ap` manages its own AP virtual interface. With WIFI_IFACE and
  # INTERNET_IFACE both pointing at the same radio (`wlan0`), it detects the
  # need for AP+STA concurrency and spawns a vif named `ap0` (the first free
  # `apN`) for the AP, leaving `wlan0` available for the STA that dogeboxd
  # configures at runtime. We don't pre-create the vif ourselves — doing so
  # forces `create_ap` to pick `ap1` instead, and using `NO_VIRT=1` to
  # override that prevents the service from starting at all on this radio.
  services.create_ap = {
    enable = lib.mkDefault true;
    settings = {
      WIFI_IFACE = "wlan0";
      INTERNET_IFACE = "wlan0";
      FREQ_BAND = "2.4";
      SSID = "Dogebox";
      PASSPHRASE = "SuchPass";
    };
  };

  # Trust the AP vif so clients connecting to the `Dogebox` SSID can reach
  # the dnsmasq instance `create_ap` runs (DHCP on UDP/67, DNS on UDP/53)
  # and dpanel/dogeboxd. Without this, the global firewall drops the DHCP
  # offer, clients fail to obtain a lease, and most phones then mark the
  # network as failed and stop showing it. `create_ap` names its auto-
  # created vif `ap0` when none exists yet.
  networking.firewall.trustedInterfaces = [ "ap0" ];

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

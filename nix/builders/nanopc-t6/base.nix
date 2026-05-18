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

  # Setup a Wi-Fi Access Point for initial configuration, while attempting to
  # also use the same Wi-Fi card as a client (STA) for upstream internet
  # access (Virtual AP / STA+AP concurrency).
  #
  # wpa_supplicant owns the STA (managed) side on wlan0; create_ap brings up
  # an AP virtual interface (ap0) on the same radio and NATs traffic out
  # through wlan0. NetworkManager is intentionally NOT used here — on this
  # rtw88 radio it conflicts with create_ap and prevents the AP from coming
  # up during initial install.
  networking.wireless.iwd.enable = false;
  networking.networkmanager.enable = false;

  # AP for initial setup — SSID/passphrase are intentionally hardcoded so the
  # user has a known, stable network to reach the dpanel on first boot.
  services.create_ap = {
    enable = lib.mkDefault true;
    settings = {
      WIFI_IFACE = "wlan0";
      INTERNET_IFACE = "wlan0";
      SHARE_METHOD = "nat";
      FREQ_BAND = "2.4";
      SSID = "Dogebox";
      PASSPHRASE = "SuchPass";
    };
  };

  # Upstream Wi-Fi (STA) credentials are provided via an environment file that
  # lives outside the Nix store, so the SSID/PSK the dogebox connects to for
  # internet access can be set before setup runs without rebuilding the image.
  # The file must define:
  #   UPSTREAM_SSID=...
  #   UPSTREAM_PSK=...
  # It should be owned by root with mode 0600 to avoid leaking the PSK.
  #
  # wpa_supplicant performs @VAR@ substitution from this file at start-up, so
  # the SSID/PSK never end up in the Nix store. wlan0 takes whatever IP the
  # upstream network's DHCP server hands out (default behaviour for
  # `networking.wireless` — no static address is configured here).
  networking.wireless.enable = true;
  networking.wireless.interfaces = [ "wlan0" ];
  networking.wireless.environmentFile = "/etc/dogebox/wifi.env";
  networking.wireless.networks."@UPSTREAM_SSID@" = {
    psk = "@UPSTREAM_PSK@";
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

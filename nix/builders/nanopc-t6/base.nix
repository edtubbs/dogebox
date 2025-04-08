{ pkgs ? import <nixpkgs> {}, lib, ... }:

{
  imports =
    # If we have an overlay for /opt specified, load that first.
    lib.optional (builtins.pathExists /etc/nixos/opt-overlay.nix) /etc/nixos/opt-overlay.nix

    ++
    [
      ./firmware.nix
      ../../dbx/base.nix
    ];

  nixpkgs.overlays = [
    (final: super: {
      makeModulesClosure = x:
        super.makeModulesClosure (x // { allowMissing = true; });

#  nixpkgs.overlays = [
#    (final: super: {
#      optee-os-rockchip-rk3588 = final.buildOptee {
#        platform = "rockchip-rk3588";
#        version = "4.5.0";
#        src = final.fetchFromGitHub {
#          owner = "OP-TEE";
#          repo = "optee_os";
#          rev = "4.5.0";
#          hash = "sha256-LzyRR0tw9dsMEyi5hGJ/IIEVV6mlHhu+0YuTomTbJ6A=";
#        };

      optee-os-rockchip-rk3588 = super.buildOptee {
        platform = "rockchip-rk3588";
        version = "8bfd4aaef4787c92ead998385437936c36da05b6";
        src = final.fetchurl {
          url = "https://github.com/edtubbs/optee_os/archive/8bfd4aaef4787c92ead998385437936c36da05b6.tar.gz";
          hash = "sha256-wL4FsbzDsQBcCHkqISv8OAJw6PIcWavNp5lAfr/NLWs=";
        };
        extraMakeFlags = [
          "CFG_TEE_CORE_LOG_LEVEL=0"
          "CFG_ATTESTATION_PTA=y"
          "CFG_ATTESTATION_PTA_KEY_SIZE=1024"
          "CFG_WITH_USER_TA=y"
          "CFG_WITH_SOFTWARE_PRNG=n"
        ];
      };

      optee-client = super.optee-client.overrideAttrs (old: {
        version = "4.5.0";
        src = final.fetchFromGitHub {
          owner = "OP-TEE";
          repo = "optee_client";
          rev = "4.5.0";
          hash = "sha256-j4ZMaop3H3yNOWdrprEwM4ALN+o9C+smprrGjbotkEs=";
        };
      });

      armTrustedFirmwareRK3588 = super.armTrustedFirmwareRK3588.overrideAttrs (old: {
        prePatch = ''
          sed -i 's/#define FDT_BUFFER_SIZE 0x20000/#define FDT_BUFFER_SIZE 0x60000/g' plat/rockchip/common/params_setup.c
        '';
        makeFlags = old.makeFlags ++ [
          "SPD=opteed"
          "LOG_LEVEL=40"
          "bl31"
        ];
      });

      ubootNanoPCT6 = super.buildUBoot {
        defconfig = "nanopc-t6-rk3588_defconfig";
        extraMeta.platforms = ["aarch64-linux"];
        extraMakeFlags = [
          "BL31=${pkgs.armTrustedFirmwareRK3588}/bl31.elf"
          "ROCKCHIP_TPL=${pkgs.rkbin.TPL_RK3588}"
          "TEE=${final.optee-os-rockchip-rk3588}/tee.bin"
        ];
        filesToInstall = [ "u-boot.itb" "idbloader.img" ];
      };

      libdogecoin-optee-ta-libs = final.stdenv.mkDerivation rec {
        pname = "libdogecoin-optee-ta-libs";
        version = "0.1.4-dogebox-enclave";
        src = final.fetchurl {
          url = "https://github.com/edtubbs/libdogecoin/archive/refs/tags/v${version}.tar.gz";
          hash = "sha256-U7Jk+/n9HmuhMM5kUuBou7YUIwNa+bOMUsoV2tIDT/Y=";
        };

        buildInputs = [
          final.autoconf
          final.automake
          final.libtool
          final.gcc
          final.curl
          final.pkg-config
          final.binutils
          (final.libunistring.overrideAttrs (old: {
            configureFlags = (old.configureFlags or []) ++ [ "--disable-shared" "--enable-static" ];
          }))
          (final.libevent.overrideAttrs (old: {
            configureFlags = (old.configureFlags or []) ++ [ "--disable-shared" "--enable-static" ];
          }))
          (final.libyubikey.overrideAttrs (old: {
            configureFlags = (old.configureFlags or []) ++ [ "--disable-shared" "--enable-static" ];
          }))
          (final.libusb1.overrideAttrs (old: {
            configureFlags = (old.configureFlags or []) ++ [ "--disable-shared" "--enable-static" ];
          }))
          (final.yubikey-personalization.overrideAttrs (old: {
            configureFlags = (old.configureFlags or []) ++ [ "--disable-shared" "--enable-static" "--with-backend=libusb-1.0" ];
          }))
          final.optee-client.dev
          final.optee-client.lib
          final.optee-os-rockchip-rk3588.devkit
        ];

        configurePhase = ''
          export HOME=$(pwd)
          export CFLAGS="$CFLAGS -Wp,-D_FORTIFY_SOURCE=0"
          ./autogen.sh
          # Force -D_FORTIFY_SOURCE=0 for the TA libs to avoid __chk references
          LIBS="-levent_core -levent_pthreads" \
            ./configure --prefix=$out --enable-static --disable-shared --enable-optee
        '';

        buildPhase = ''
          export HOME=$(pwd)
          make
        '';
      };

      libdogecoin-optee-host-libs = final.stdenv.mkDerivation rec {
        pname = "libdogecoin-optee-host-libs";
        version = "0.1.4-dogebox-enclave";
        src = final.fetchurl {
          url = "https://github.com/edtubbs/libdogecoin/archive/refs/tags/v${version}.tar.gz";
          hash = "sha256-U7Jk+/n9HmuhMM5kUuBou7YUIwNa+bOMUsoV2tIDT/Y=";
        };

        buildInputs = [
          final.autoconf
          final.automake
          final.libtool
          final.gcc
          final.curl
          final.pkg-config
          final.binutils
          (final.libunistring.overrideAttrs (old: {
            configureFlags = (old.configureFlags or []) ++ [ "--disable-shared" "--enable-static" ];
          }))
          (final.libevent.overrideAttrs (old: {
            configureFlags = (old.configureFlags or []) ++ [ "--disable-shared" "--enable-static" ];
          }))
          (final.libyubikey.overrideAttrs (old: {
            configureFlags = (old.configureFlags or []) ++ [ "--disable-shared" "--enable-static" ];
          }))
          (final.libusb1.overrideAttrs (old: {
            configureFlags = (old.configureFlags or []) ++ [ "--disable-shared" "--enable-static" ];
          }))
          (final.yubikey-personalization.overrideAttrs (old: {
            configureFlags = (old.configureFlags or []) ++ [ "--disable-shared" "--enable-static" "--with-backend=libusb-1.0" ];
          }))
          final.optee-client.dev
          final.optee-client.lib
          final.optee-os-rockchip-rk3588.devkit
        ];

        configurePhase = ''
          export HOME=$(pwd)
          ./autogen.sh
          LIBS="-levent_core -levent_pthreads" \
            ./configure --prefix=$out --enable-static --disable-shared
        '';

        buildPhase = ''
          export HOME=$(pwd)
          make
        '';
      };

      libdogecoin-optee-host = final.stdenv.mkDerivation rec {
        pname = "libdogecoin-optee-host";
        version = "0.1.4-dogebox-enclave";
        src = final.fetchurl {
          url = "https://github.com/edtubbs/libdogecoin/archive/refs/tags/v${version}.tar.gz";
          hash = "sha256-U7Jk+/n9HmuhMM5kUuBou7YUIwNa+bOMUsoV2tIDT/Y=";
        };
        buildInputs = [
          final.autoconf
          final.automake
          final.libtool
          final.gcc
          final.curl
          final.pkg-config
          final.binutils
          final.optee-client.dev
          final.optee-client.lib
          final.optee-os-rockchip-rk3588.devkit
          final.libdogecoin-optee-host-libs
          final.yubikey-personalization
          final.libusb1
          final.libyubikey
        ];
        buildPhase = ''
          export HOME=$(pwd)
          cd src/optee/host
          make \
            LDFLAGS="-L${final.libdogecoin-optee-host-libs}/lib -ldogecoin" \
            CFLAGS="-I${final.libdogecoin-optee-host-libs}/include -I${final.libdogecoin-optee-host-libs}/include/dogecoin -I${final.optee-client.dev}/include -I${final.yubikey-personalization}/include/ykpers-1 -I$HOME/src/optee/ta/include"
        '';
        installPhase = ''
          mkdir -p $out/bin
          cp optee_libdogecoin $out/bin/
          chmod 777 $out/bin/optee_libdogecoin
        '';
      };

      libdogecoin-optee-ta = final.stdenv.mkDerivation rec {
        pname = "libdogecoin-optee-ta";
        version = "0.1.4-dogebox-enclave";
        src = final.fetchurl {
          url = "https://github.com/edtubbs/libdogecoin/archive/refs/tags/v${version}.tar.gz";
          hash = "sha256-U7Jk+/n9HmuhMM5kUuBou7YUIwNa+bOMUsoV2tIDT/Y=";
        };
        buildInputs = [
          final.autoconf
          final.automake
          final.libtool
          final.gcc
          final.curl
          final.pkg-config
          final.python3
          final.python3Packages.cryptography
          final.binutils
          (final.libunistring.overrideAttrs (old: {
            configureFlags = (old.configureFlags or []) ++ [ "--disable-shared" "--enable-static" "CFLAGS=-Wp,-D_FORTIFY_SOURCE=0" ];
          }))
          (final.libevent.overrideAttrs (old: {
            configureFlags = (old.configureFlags or []) ++ [ "--disable-shared" "--enable-static" "CFLAGS=-Wp,-D_FORTIFY_SOURCE=0" ];
          }))
          (final.libyubikey.overrideAttrs (old: {
            configureFlags = (old.configureFlags or []) ++ [ "--disable-shared" "--enable-static" "CFLAGS=-Wp,-D_FORTIFY_SOURCE=0" ];
          }))
          (final.libusb1.overrideAttrs (old: {
            configureFlags = (old.configureFlags or []) ++ [ "--disable-shared" "--enable-static" "CFLAGS=-Wp,-D_FORTIFY_SOURCE=0" ];
          }))
          (final.yubikey-personalization.overrideAttrs (old: {
            configureFlags = (old.configureFlags or []) ++ [ "--disable-shared" "--enable-static" "--with-backend=libusb-1.0" "CFLAGS=-Wp,-D_FORTIFY_SOURCE=0" ];
          }))
          final.optee-client.dev
          final.optee-client.lib
          final.optee-os-rockchip-rk3588
          final.optee-os-rockchip-rk3588.devkit
          final.libdogecoin-optee-ta-libs
        ];
        buildPhase = ''
          export HOME=$(pwd)
          cd src/optee/ta
          make \
            PLATFORM=rockchip-rk3588 \
            LIBDIR="${final.libdogecoin-optee-ta-libs}/lib" \
            LDFLAGS="-L${final.libdogecoin-optee-ta-libs}/lib -ldogecoin -lunistring" \
            CFLAGS="-I${final.libdogecoin-optee-ta-libs}/include -I${final.libdogecoin-optee-ta-libs}/include/dogecoin" \
            TA_DEV_KIT_DIR=${final.optee-os-rockchip-rk3588.devkit}
        '';
        installPhase = ''
          mkdir -p $out/ta
          cp 62d95dc0-7fc2-4cb3-a7f3-c13ae4e633c4.ta $out/ta/
        '';
      };
    })
  ];

  # Show everything in the tty console instead of serial.
  boot.kernelParams = [ "console=ttyFIQ0" ];

  # Use the extlinux boot loader. (NixOS wants to enable GRUB by default)
  boot.loader.grub.enable = false;
  # Enables the generation of /boot/extlinux/extlinux.conf
  boot.loader.generic-extlinux-compatible.enable = true;
  boot.loader.timeout = 1;

  boot.kernelPackages = let
    linux_rk3588_pkg = {
      fetchFromGitHub,
      linuxManualConfig,
      ubootTools,
      ...
    } :
    (linuxManualConfig rec {
      modDirVersion = "6.1.57";
      version = modDirVersion;

      src = fetchFromGitHub {
        owner = "friendlyarm";
        repo = "kernel-rockchip";
        rev = "85d0764ec61ebfab6b0d9f6c65f2290068a46fa1";
        hash = "sha256-oGMx0EYfPQb8XxzObs8CXgXS/Q9pE1O5/fP7/ehRUDA=";
      };

      configfile = ./nanopc-T6_linux_defconfig;
      allowImportFromDerivation = true;
    })
    .overrideAttrs (old: {
      nativeBuildInputs = old.nativeBuildInputs ++ [ubootTools];
      prePatch = ''
        patch -p1 < ${./rk3588-nanopi6-common.dtsi.patch}
        cp arch/arm64/boot/dts/rockchip/rk3588-nanopi6-rev01.dts arch/arm64/boot/dts/rockchip/rk3588-nanopc-t6.dts
        sed -i "s/rk3588-nanopi6-rev0a.dtb/rk3588-nanopi6-rev0a.dtb\ rk3588-nanopc-t6.dtb/" arch/arm64/boot/dts/rockchip/Makefile
      '';
      makeFlags = (old.makeFlags or []) ++ [ "KCFLAGS=-Wno-error" ];
    });
      linux_rk3588 = pkgs.callPackage linux_rk3588_pkg{};
    in
      pkgs.recurseIntoAttrs (pkgs.linuxPackagesFor linux_rk3588);

  boot.initrd.availableKernelModules = [ "nvme" "usbhid" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "rtw88_8822ce" "rtw88_pci" "rtw88_core" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" =
    { device = "/dev/disk/by-label/nixos";
      fsType = "ext4";
    };

  environment.systemPackages = with pkgs; [
    cloud-utils
    parted
    gptfdisk
    wpa_supplicant
    screen
  ];

  systemd.services.resizerootfs = {
    description = "Expands root filesystem of boot deviceon first boot";
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
    wantedBy = [ "basic.target" "runOnceOnFirstBoot.service" ];
  };

}

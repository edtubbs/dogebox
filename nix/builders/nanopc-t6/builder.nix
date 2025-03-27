{ pkgs ? import <nixpkgs> {}, modulesPath, lib, config, dbxRelease, ... }:

let
  dogebox = import <dogebox> { inherit pkgs; };

  nanopc-T6File = pkgs.writeTextFile {
    name = "nanopc-T6.nix";
    text = builtins.readFile ./base.nix;
  };

  kernelConfigFile = pkgs.writeTextFile {
    name = "nanopc-T6_linux_defconfig";
    text = builtins.readFile ./nanopc-T6_linux_defconfig;
  };

  kernelPatchFile = pkgs.writeTextFile {
    name = "rk3588-nanopi6-common.dtsi.patch";
    text = builtins.readFile ./rk3588-nanopi6-common.dtsi.patch;
  };

  baseFile = pkgs.writeTextFile {
    name = "base.nix";
    text = builtins.readFile ../../dbx/base.nix;
  };

  dogeboxFile = pkgs.writeTextFile {
    name = "dogebox.nix";
    text = builtins.readFile ../../dbx/dogebox.nix;
  };

  dogeboxdFile = pkgs.writeTextFile {
    name = "dogeboxd.nix";
    text = builtins.readFile ../../dbx/dogeboxd.nix;
  };

  dkmFile = pkgs.writeTextFile {
    name = "dkm.nix";
    text = builtins.readFile ../../dbx/dkm.nix;
  };

  firmwareFile = pkgs.writeTextFile {
    name = "firmware.nix";
    text = builtins.readFile ./firmware.nix;
  };

  imageName = "dogebox-${dbxRelease}-t6";

  # Override make-disk-image to pass in values that aren't properly exposed via nixos-generators
  # https://github.com/nix-community/nixos-generators/blob/master/formats/raw.nix#L23-L27
  baseRawImage = import "${toString modulesPath}/../lib/make-disk-image.nix" {
    inherit lib config pkgs;
    diskSize = "auto";
    format = "raw";
    name = imageName;
  };
in
{
  imports = [
    ./base.nix
  ];

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
  nixpkgs.overlays = [
    (final: super: {
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
        prePatch = ''
          patch -p1 < ${./rockchip-u-boot.dtsi.patch}
        '';
        extraMakeFlags = [
          "BL31=${pkgs.armTrustedFirmwareRK3588}/bl31.elf"
          "ROCKCHIP_TPL=${pkgs.rkbin.TPL_RK3588}"
          "TEE=${final.optee-os-rockchip-rk3588}/tee-raw.bin"
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

  services.tee-supplicant = {
    enable = true;

    trustedApplications = [
      "${pkgs.optee-os-rockchip-rk3588.devkit}/ta/023f8f1a-292a-432b-8fc4-de8471358067.ta"
      "${pkgs.optee-os-rockchip-rk3588.devkit}/ta/80a4c275-0a47-4905-8285-1486a9771a08.ta"
      "${pkgs.optee-os-rockchip-rk3588.devkit}/ta/f04a0fe7-1f5d-4b9b-abf7-619b85b4ce8c.ta"
      "${pkgs.optee-os-rockchip-rk3588.devkit}/ta/fd02c9da-306c-48c7-a49c-bbd827ae86ee.ta"
      "${pkgs.libdogecoin-optee-ta}/ta/62d95dc0-7fc2-4cb3-a7f3-c13ae4e633c4.ta"
    ];
  };

  # These aren't used directly, but are consumed by ubootNanoPCT6 so need to be explicitly whitelisted.
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "arm-trusted-firmware-rk3588"
    "rkbin"
  ];

  environment.systemPackages = with pkgs; [
    cloud-utils
    parted
    gptfdisk
    wpa_supplicant
    screen
    optee-os-rockchip-rk3588
    optee-client
    libdogecoin-optee-host
    libdogecoin-optee-ta
  ];

  system.build.raw = lib.mkForce (pkgs.stdenv.mkDerivation {
    name = "dogebox-t6.img";
    src = ./.;
    buildInputs = [
      baseRawImage
      pkgs.bash
      pkgs.parted
      pkgs.simg2img
    ];
    buildCommand = ''
      mkdir -p $out

      ln -s ${pkgs.ubootNanoPCT6}/idbloader.img $out/idbloader.img
      ln -s ${pkgs.ubootNanoPCT6}/u-boot.itb $out/uboot.img
      ${pkgs.bash}/bin/bash $src/scripts/extract-fs-from-disk-image.sh ${baseRawImage}/nixos.img $out/
      cp $src/templates/parameter.txt $out/
      ${pkgs.bash}/bin/bash $src/scripts/make-sd-image.sh $out/ ${imageName}.img

      # Only copy the resulting image, we don't care about other intermediaries.
      mv $out/dogebox-*.img /tmp
      rm -Rf $out/*
      mv /tmp/dogebox-*.img $out/
    '';
  });

  system.activationScripts.copyFiles = ''
    mkdir -p /opt
    echo "nanopc-T6" > /opt/build-type

    # Even though the T6 image can technically run off the microsd card
    # the EMMC is going to be a much better experience, so force installation.

    # Annoyingly, this script gets run even on a post-installed T6 image, so we need
    # to ensure that we don't re-mark an installed version as RO.
    if [ ! -f /opt/dbx-installed ]; then
      touch /opt/ro-media
    fi

    cp ${nanopc-T6File} /etc/nixos/configuration.nix
    cp ${kernelConfigFile} /etc/nixos/nanopc-T6_linux_defconfig
    cp ${kernelPatchFile} /etc/nixos/rk3588-nanopi6-common.dtsi.patch
    cp ${baseFile} /etc/nixos/base.nix
    cp ${dogeboxFile} /etc/nixos/dogebox.nix
    cp ${dogeboxdFile} /etc/nixos/dogeboxd.nix
    cp ${dkmFile} /etc/nixos/dkm.nix
    cp ${firmwareFile} /etc/nixos/firmware.nix
  '';
}

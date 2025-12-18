self: super:

let
  optee-os-pkgs = import ./pkgs/optee-os/default.nix {
    inherit (super)
      stdenv
      fetchFromGitHub
      dtc
      lib
      pkgsBuildBuild
      ;
  };
in
{
  optee-client = import ./pkgs/by-name/op/optee-client/package.nix {
    inherit (super)
      stdenv
      fetchFromGitHub
      lib
      libuuid
      pkg-config
      which
      ;
  };

  optee-os-rockchip-rk3588 = optee-os-pkgs.buildOptee {
    platform = "rockchip_rk3588";
    extraMakeFlags = [ "CFG_ARM64_core=y" ];
    extraMeta.platforms = [ "aarch64-linux" ];
  };

  # Re-export optee-os
  inherit (optee-os-pkgs) buildOptee opteeQemuArm opteeQemuAarch64;

  # Export tee-supplicant
  nixosModules.tee-supplicant = import ./modules/tee-supplicant/default.nix;

  libdogecoin-optee-ta-libs = super.stdenv.mkDerivation rec {
    pname = "libdogecoin-optee-ta-libs";
    version = "0.1.5-pre";
    src = super.fetchurl {
      url = "https://github.com/dogecoinfoundation/libdogecoin/archive/refs/tags/v${version}.tar.gz";
      hash = "sha256-oQMR0EzzRcsfZ3DoKnESXanEjm6dk2X+7zFhL+Ae6cs=";
    };

    buildInputs = [
      super.autoconf
      super.automake
      super.libtool
      super.gcc
      super.curl
      super.pkg-config
      super.binutils
      (super.libunistring.overrideAttrs (old: {
        configureFlags = (old.configureFlags or [ ]) ++ [
          "--disable-shared"
          "--enable-static"
        ];
      }))
      (super.libevent.overrideAttrs (old: {
        configureFlags = (old.configureFlags or [ ]) ++ [
          "--disable-shared"
          "--enable-static"
        ];
      }))
      (super.libyubikey.overrideAttrs (old: {
        configureFlags = (old.configureFlags or [ ]) ++ [
          "--disable-shared"
          "--enable-static"
        ];
      }))
      (super.libusb1.overrideAttrs (old: {
        configureFlags = (old.configureFlags or [ ]) ++ [
          "--disable-shared"
          "--enable-static"
        ];
      }))
      (super.yubikey-personalization.overrideAttrs (old: {
        configureFlags = (old.configureFlags or [ ]) ++ [
          "--disable-shared"
          "--enable-static"
          "--with-backend=libusb-1.0"
        ];
      }))
      self.optee-client.dev
      self.optee-client.lib
      self.optee-os-rockchip-rk3588.devkit
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

  libdogecoin-optee-host-libs = super.stdenv.mkDerivation rec {
    pname = "libdogecoin-optee-host-libs";
    version = "0.1.5-pre";
    src = super.fetchurl {
      url = "https://github.com/dogecoinfoundation/libdogecoin/archive/refs/tags/v${version}.tar.gz";
      hash = "sha256-oQMR0EzzRcsfZ3DoKnESXanEjm6dk2X+7zFhL+Ae6cs=";
    };

    buildInputs = [
      super.autoconf
      super.automake
      super.libtool
      super.gcc
      super.curl
      super.pkg-config
      super.binutils
      (super.libunistring.overrideAttrs (old: {
        configureFlags = (old.configureFlags or [ ]) ++ [
          "--disable-shared"
          "--enable-static"
        ];
      }))
      (super.libevent.overrideAttrs (old: {
        configureFlags = (old.configureFlags or [ ]) ++ [
          "--disable-shared"
          "--enable-static"
        ];
      }))
      (super.libyubikey.overrideAttrs (old: {
        configureFlags = (old.configureFlags or [ ]) ++ [
          "--disable-shared"
          "--enable-static"
        ];
      }))
      (super.libusb1.overrideAttrs (old: {
        configureFlags = (old.configureFlags or [ ]) ++ [
          "--disable-shared"
          "--enable-static"
        ];
      }))
      (super.yubikey-personalization.overrideAttrs (old: {
        configureFlags = (old.configureFlags or [ ]) ++ [
          "--disable-shared"
          "--enable-static"
          "--with-backend=libusb-1.0"
        ];
      }))
      self.optee-client.dev
      self.optee-client.lib
      self.optee-os-rockchip-rk3588.devkit
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

  libdogecoin-optee-host = super.stdenv.mkDerivation rec {
    pname = "libdogecoin-optee-host";
    version = "0.1.5-pre";
    src = super.fetchurl {
      url = "https://github.com/dogecoinfoundation/libdogecoin/archive/refs/tags/v${version}.tar.gz";
      hash = "sha256-oQMR0EzzRcsfZ3DoKnESXanEjm6dk2X+7zFhL+Ae6cs=";
    };
    buildInputs = [
      super.autoconf
      super.automake
      super.libtool
      super.gcc
      super.curl
      super.pkg-config
      super.binutils
      self.optee-client.dev
      self.optee-client.lib
      self.optee-os-rockchip-rk3588.devkit
      self.libdogecoin-optee-host-libs
      super.yubikey-personalization
      super.libusb1
      super.libyubikey
    ];
    buildPhase = ''
      export HOME=$(pwd)
      cd src/optee/host
      make \
        LDFLAGS="-L${self.libdogecoin-optee-host-libs}/lib -ldogecoin" \
        CFLAGS="-I${self.libdogecoin-optee-host-libs}/include -I${self.libdogecoin-optee-host-libs}/include/dogecoin -I${self.optee-client.dev}/include -I${super.yubikey-personalization}/include/ykpers-1 -I$HOME/src/optee/ta/include"
    '';
    installPhase = ''
      mkdir -p $out/bin
      cp optee_libdogecoin $out/bin/
      chmod 777 $out/bin/optee_libdogecoin
    '';
  };

  libdogecoin-optee-ta = super.stdenv.mkDerivation rec {
    pname = "libdogecoin-optee-ta";
    version = "0.1.5-pre";
    src = super.fetchurl {
      url = "https://github.com/dogecoinfoundation/libdogecoin/archive/refs/tags/v${version}.tar.gz";
      hash = "sha256-oQMR0EzzRcsfZ3DoKnESXanEjm6dk2X+7zFhL+Ae6cs=";
    };
    buildInputs = [
      super.autoconf
      super.automake
      super.libtool
      super.gcc
      super.curl
      super.pkg-config
      super.python3
      super.python3Packages.cryptography
      super.binutils
      (super.libunistring.overrideAttrs (old: {
        configureFlags = (old.configureFlags or [ ]) ++ [
          "--disable-shared"
          "--enable-static"
          "CFLAGS=-Wp,-D_FORTIFY_SOURCE=0"
        ];
      }))
      (super.libevent.overrideAttrs (old: {
        configureFlags = (old.configureFlags or [ ]) ++ [
          "--disable-shared"
          "--enable-static"
          "CFLAGS=-Wp,-D_FORTIFY_SOURCE=0"
        ];
      }))
      (super.libyubikey.overrideAttrs (old: {
        configureFlags = (old.configureFlags or [ ]) ++ [
          "--disable-shared"
          "--enable-static"
          "CFLAGS=-Wp,-D_FORTIFY_SOURCE=0"
        ];
      }))
      (super.libusb1.overrideAttrs (old: {
        configureFlags = (old.configureFlags or [ ]) ++ [
          "--disable-shared"
          "--enable-static"
          "CFLAGS=-Wp,-D_FORTIFY_SOURCE=0"
        ];
      }))
      (super.yubikey-personalization.overrideAttrs (old: {
        configureFlags = (old.configureFlags or [ ]) ++ [
          "--disable-shared"
          "--enable-static"
          "--with-backend=libusb-1.0"
          "CFLAGS=-Wp,-D_FORTIFY_SOURCE=0"
        ];
      }))
      self.optee-client.dev
      self.optee-client.lib
      self.optee-os-rockchip-rk3588
      self.optee-os-rockchip-rk3588.devkit
      self.libdogecoin-optee-ta-libs
    ];
    buildPhase = ''
      export HOME=$(pwd)
      cd src/optee/ta
      make \
        PLATFORM=rockchip-rk3588 \
        LIBDIR="${self.libdogecoin-optee-ta-libs}/lib" \
        LDFLAGS="-L${self.libdogecoin-optee-ta-libs}/lib -ldogecoin -lunistring" \
        CFLAGS="-I${self.libdogecoin-optee-ta-libs}/include -I${self.libdogecoin-optee-ta-libs}/include/dogecoin" \
        TA_DEV_KIT_DIR=${self.optee-os-rockchip-rk3588.devkit}
    '';
    installPhase = ''
      mkdir -p $out/ta
      cp 62d95dc0-7fc2-4cb3-a7f3-c13ae4e633c4.ta $out/ta/
    '';
  };
}

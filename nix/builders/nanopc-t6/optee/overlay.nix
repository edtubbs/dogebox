self: super:
{
  libdogecoin-optee-ta-libs = super.stdenv.mkDerivation rec {
    pname = "libdogecoin-optee-ta-libs";
    version = "0.1.5-pre-snapshot-optee";
    src = super.fetchurl {
      url = "https://github.com/edtubbs/libdogecoin/archive/refs/tags/v${version}.tar.gz";
      hash = "sha256-RMMiwe4hir0BIj3jxZJj1bJeAz6kAUNC52ZHbiI4cxs=";
    };

    nativeBuildInputs = [
      super.autoconf
      super.automake
      super.libtool
      super.curl
      super.pkg-config
    ];
    buildInputs = [
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
      super.libevent.dev
      super.optee-client.dev
      super.optee-client.lib
    ];

    configurePhase = ''
      export HOME=$(pwd)
      export CFLAGS="$CFLAGS -Wp,-D_FORTIFY_SOURCE=0"
      export ac_cv_prog_cc_works=yes
      ./autogen.sh
      # Force -D_FORTIFY_SOURCE=0 for the TA libs to avoid __chk references
      LIBS="-levent_core -levent_pthreads" \
        ./configure --prefix=$out --enable-static --disable-shared --enable-optee \
          --build=${super.stdenv.buildPlatform.config} \
          --host=${super.stdenv.hostPlatform.config}
    '';

    buildPhase = ''
      export HOME=$(pwd)
      make
    '';
  };

  libdogecoin-optee-host-libs = super.stdenv.mkDerivation rec {
    pname = "libdogecoin-optee-host-libs";
    version = "0.1.5-pre-snapshot-optee";
    src = super.fetchurl {
      url = "https://github.com/edtubbs/libdogecoin/archive/refs/tags/v${version}.tar.gz";
      hash = "sha256-RMMiwe4hir0BIj3jxZJj1bJeAz6kAUNC52ZHbiI4cxs=";
    };

    nativeBuildInputs = [
      super.autoconf
      super.automake
      super.libtool
      super.curl
      super.pkg-config
    ];
    buildInputs = [
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
      super.libevent.dev
      super.optee-client.dev
      super.optee-client.lib
    ];

    configurePhase = ''
      export HOME=$(pwd)
      export ac_cv_prog_cc_works=yes
      ./autogen.sh
      LIBS="-levent_core -levent_pthreads" \
        ./configure --prefix=$out --enable-static --disable-shared \
          --build=${super.stdenv.buildPlatform.config} \
          --host=${super.stdenv.hostPlatform.config}
    '';

    buildPhase = ''
      export HOME=$(pwd)
      make
    '';
  };

  libdogecoin-optee-host = super.stdenv.mkDerivation rec {
    pname = "libdogecoin-optee-host";
    version = "0.1.5-pre-snapshot-optee";
    src = super.fetchurl {
      url = "https://github.com/edtubbs/libdogecoin/archive/refs/tags/v${version}.tar.gz";
      hash = "sha256-RMMiwe4hir0BIj3jxZJj1bJeAz6kAUNC52ZHbiI4cxs=";
    };
    nativeBuildInputs = [
      super.autoconf
      super.automake
      super.libtool
      super.gcc
      super.curl
      super.pkg-config
    ];
    buildInputs = [
      super.optee-client.dev
      super.optee-client.lib
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
        CFLAGS="-I${self.libdogecoin-optee-host-libs}/include -I${self.libdogecoin-optee-host-libs}/include/dogecoin -I${super.optee-client.dev}/include -I${super.yubikey-personalization}/include/ykpers-1 -I${super.libusb1}/include -I${super.libyubikey}/include -I$HOME/src/optee/ta/include"
    '';
    installPhase = ''
      mkdir -p $out/bin
      cp optee_libdogecoin $out/bin/
      chmod 777 $out/bin/optee_libdogecoin
    '';
  };

  libdogecoin-optee-ta = super.stdenv.mkDerivation rec {
    pname = "libdogecoin-optee-ta";
    version = "0.1.5-pre-snapshot-optee";
    src = super.fetchurl {
      url = "https://github.com/edtubbs/libdogecoin/archive/refs/tags/v${version}.tar.gz";
      hash = "sha256-RMMiwe4hir0BIj3jxZJj1bJeAz6kAUNC52ZHbiI4cxs=";
    };
    nativeBuildInputs = [
      super.autoconf
      super.automake
      super.libtool
      super.curl
      super.pkg-config
      super.python3
      super.python3Packages.cryptography
    ];
    buildInputs = [
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
      super.optee-client.dev
      super.optee-client.lib
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

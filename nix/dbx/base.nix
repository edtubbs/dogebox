{ lib, pkgs, ... }:

{
  imports = [
    ./dogebox.nix
  ]
  ++ lib.optionals (builtins.pathExists "/etc/nixos/hardware-configuration.nix") [
    /etc/nixos/hardware-configuration.nix
  ];

  nix.settings = {
    auto-optimise-store = false;
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    require-sigs = true;
    sandbox = true;
    sandbox-fallback = false;
    substituters = [
      "https://cache.nixos.org/"
      "https://dbx.nix.dogecoin.org"
    ];

    # Make on-device `nixos-rebuild switch` survive having no upstream
    # network — the very thing it's about to configure.
    #
    # When dogeboxd saves a user-entered STA wifi config it runs
    # `nixos-rebuild switch` to apply it. At that moment the box is
    # only reachable over the setup AP (`ap0`) and has no upstream
    # DNS yet. The rebuild was failing on `Could not resolve host:
    # github.com` while re-validating an already-locked flake input
    # (e.g. `dogebox-wg/dkm` at the rev pinned in flake.lock), then
    # rolling back — so the STA config never took effect and dual
    # mode never came up.
    #
    # For a pure config swap nothing actually needs to be fetched:
    # flake inputs are pinned in `/etc/nixos/flake.lock` and their
    # store paths were placed during the original image build.
    #
    #   - `fallback = true`: if substituters are unreachable, fall back
    #     to the local store / local build instead of aborting. There's
    #     nothing to build here, so this just lets the rebuild succeed.
    #   - `tarball-ttl = 31536000`: don't re-validate locked github
    #     flake inputs against github.com for a year. The lockfile
    #     already pins narHashes; the default 1 h TTL is what triggers
    #     the DNS lookup that kills the rebuild.
    fallback = true;
    tarball-ttl = 31536000;

    system-features = [
      "nixos-test"
      "benchmark"
      "big-parallel"
      "kvm"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "dbx.nix.dogecoin.org:ODXaHC+9DNqXQ8ZTijaCT4JpieqmOatZeZBbdN51Obc="
    ];
    trusted-users = [
      "root"
      "nixos"
    ];
  };

  # Set your time zone.
  time.timeZone = lib.mkDefault "Australia/Brisbane";

  environment.systemPackages = with pkgs; [
    # Install a few utility packages
    git
    vim
    wget
    wirelesstools
  ];

  # DO NOT CHANGE THIS. EVER. EVEN WHEN UPDATING YOUR SYSTEM PAST 25.05.
  system.stateVersion = lib.mkDefault "25.05";
}

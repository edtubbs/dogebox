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

    # When dogeboxd saves a user-entered STA wifi config it runs
    # `nixos-rebuild switch` to apply it. At that moment the box is
    # only reachable over the setup AP (`ap0`) and has no upstream
    # DNS yet, so substituters are unreachable. Falling back to the
    # local store lets that rebuild succeed — nothing needs to be
    # fetched, since flake inputs are already pinned in flake.lock
    # and their store paths were placed during image build.
    # (dogeboxd also passes `--no-update-lock-file` so locked inputs
    # are not re-validated against github.com.)
    fallback = true;

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

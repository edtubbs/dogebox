{
  fetchFromGitHub,
  linuxManualConfig,
  ...
}:

let
  modDirVersion = "6.1.75";
in
linuxManualConfig {
  inherit modDirVersion;
  version = "${modDirVersion}-jr-noble";
  extraMeta.branch = "6.1";

  src = fetchFromGitHub {
    owner = "Joshua-Riek";
    repo = "linux-rockchip";
    rev = "5c43412639fd134f0ba690de2108eaa7ea349e2a";
    hash = "sha256-aKm/RQTRTzLr8+ACdG6QW1LWn+ZOjQtlvU2KkZmYicg=";
  };

  configfile = ./nanopc-T6_linux_defconfig;
}

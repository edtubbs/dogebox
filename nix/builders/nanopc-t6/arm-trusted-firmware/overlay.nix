self: super:

let
  atf = import ./default.nix {
    inherit (super)
      lib
      stdenv
      fetchFromGitHub
      fetchFromGitLab
      openssl
      pkgsCross
      buildPackages
      ;
  };
in
{
  armTrustedFirmwareRK3588 = atf.armTrustedFirmwareRK3588;
  armTrustedFirmwareTools = atf.armTrustedFirmwareTools;
}

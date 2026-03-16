{
  config,
  lib,
  pkgs,
  dkm,
  devMode,
  ...
}:

let
  opteeOsRockchip = lib.attrByPath [ "optee-os-rockchip-rk3588" ] null pkgs;
  hasOpteeOs = opteeOsRockchip != null;
in
{
  users.users.dkm = {
    isSystemUser = true;
    group = "dogebox";
    extraGroups = [ ];
  };

  systemd.tmpfiles.rules = [
    "d /opt/dkm 0700 dkm dogebox -"
  ];

  systemd.services.dkm = {
    enable = !devMode;
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      ExecStart = "${dkm}/bin/dkm --dir /opt/dkm";
      Restart = "always";
      User = "dkm";
      Group = "dogebox";
    };
  };

  services.tee-supplicant = lib.mkIf hasOpteeOs {
    enable = true;
    trustedApplications =
      [
        "${opteeOsRockchip.devkit}/ta/023f8f1a-292a-432b-8fc4-de8471358067.ta"
        "${opteeOsRockchip.devkit}/ta/80a4c275-0a47-4905-8285-1486a9771a08.ta"
        "${opteeOsRockchip.devkit}/ta/f04a0fe7-1f5d-4b9b-abf7-619b85b4ce8c.ta"
        "${opteeOsRockchip.devkit}/ta/fd02c9da-306c-48c7-a49c-bbd827ae86ee.ta"
      ];
  };
}

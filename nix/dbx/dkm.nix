{
  config,
  lib,
  pkgs,
  dkm,
  devMode,
  inputs,
  ...
}:

let
  opteeOsRockchip = lib.attrByPath [ "optee-os-rockchip-rk3588" ] null pkgs;
  hasOpteeOs = opteeOsRockchip != null;
  libdogecoinTaUuid = "62d95dc0-7fc2-4cb3-a7f3-c13ae4e633c4";
  libdogecoinTaWaitTimeoutSeconds = 1800;
  libdogecoinFromNur = pkgs.callPackage "${inputs.dogebox-nur-packages}/pkgs/libdogecoin/default.nix" { };
  libdogecoinOpteeTaPath = "${libdogecoinFromNur.libdogecoin-optee-ta}/ta/${libdogecoinTaUuid}.ta";
in
{
  environment.systemPackages = lib.optionals hasOpteeOs [
    libdogecoinFromNur.libdogecoin-optee-host
  ];

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
    after = [ "network.target" ] ++ lib.optionals hasOpteeOs [ "tee-supplicant.service" ];
    requires = lib.optionals hasOpteeOs [ "tee-supplicant.service" ];
    path = lib.optionals hasOpteeOs [ libdogecoinFromNur.libdogecoin-optee-host ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      ExecStartPre = lib.optionals hasOpteeOs [
        ''
          ${pkgs.runtimeShell} -c 'deadline=$((${pkgs.coreutils}/bin/date +%s + ${toString libdogecoinTaWaitTimeoutSeconds})); while [ ! -f /lib/optee_armtz/${libdogecoinTaUuid}.ta ]; do if [ "$(${pkgs.coreutils}/bin/date +%s)" -ge "$deadline" ]; then echo "libdogecoin OP-TEE TA not installed at /lib/optee_armtz/${libdogecoinTaUuid}.ta after ${toString libdogecoinTaWaitTimeoutSeconds}s" >&2; exit 1; fi; ${pkgs.coreutils}/bin/sleep 1; done'
        ''
      ];
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
        libdogecoinOpteeTaPath
      ];
  };
}

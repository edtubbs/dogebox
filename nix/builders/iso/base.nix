{ lib, targetToplevel ? null, ... }:

{
  fileSystems = lib.mkDefault {
    "/" = {
      device = "/dev/disk/by-label/nixos";
      autoResize = true;
      fsType = "ext4";
    };
  };
  boot.growPartition = true;
  boot.loader.grub.device = lib.mkDefault "/dev/sda";
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;
  boot.loader.systemd-boot.enable = lib.mkDefault true;

  # Bake the target system closure into the ISO for offline installs.
  isoImage.storeContents = lib.mkIf (targetToplevel != null) [ targetToplevel ];
  environment.etc."dogebox/target-toplevel" = lib.mkIf (targetToplevel != null) {
    text = "${targetToplevel}";
  };
  system.activationScripts.writeTargetToplevel = lib.mkIf (targetToplevel != null) (lib.mkForce "");
}

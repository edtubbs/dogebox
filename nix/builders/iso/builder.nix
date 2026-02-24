{
  lib,
  arch,
  self,
  builderType,
  dbxRelease,
  ...
}:

let
  targetToplevel =
    self.nixosConfigurations."dogeboxos-${builderType}-${arch}".config.system.build.toplevel;
in
{
  image.baseName = lib.mkForce "dogebox-${dbxRelease}-${arch}";
  isoImage.prependToMenuLabel = "DogeboxOS (";
  isoImage.appendToMenuLabel = ")";

  # Bake the target system closure into the ISO for offline installs.
  isoImage.storeContents = [ targetToplevel ];
  environment.etc."dogebox/target-toplevel".text = "${targetToplevel}";
}

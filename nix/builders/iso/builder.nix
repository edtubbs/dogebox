{
  lib,
  arch,
  dbxRelease,
  ...
}:

{
  image.baseName = lib.mkForce "dogebox-${dbxRelease}-${arch}";
  isoImage.prependToMenuLabel = "DogeboxOS (";
  isoImage.appendToMenuLabel = ")";
}

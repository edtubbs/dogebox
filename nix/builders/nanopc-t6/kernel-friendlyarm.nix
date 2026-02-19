{
  buildLinux,
  fetchFromGitHub,
  ...
} @ args:
buildLinux (args // {
  version = "6.1.141";
  modDirVersion = "6.1.141";

  src = fetchFromGitHub {
    owner = "friendlyarm";
    repo = "kernel-rockchip";
    rev = "524e3e035d50fcc8a623cf8e487cfb35d7272ffa";
    hash = "sha256-ihACbK4TkO/frqPnfX6mOu07i/NzH5lgFllkQi8PgUI=";
  };

  defconfig = "nanopi6_linux_defconfig";
})

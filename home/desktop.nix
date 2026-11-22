# Home profile for the desktop only (imported by modules/desktop.nix).
# Anything both machines need belongs in home/shared.nix or home/graphical.nix.
{
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    alcom # VRChat package manager (successor to VCC)
    unityhub
    cudaPackages.cudatoolkit # nvcc + CUDA libraries for local work
  ];
}

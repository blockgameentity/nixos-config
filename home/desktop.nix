# Home profile for the desktop only (imported by modules/desktop.nix).
# Anything both machines need belongs in home/shared.nix or home/graphical.nix.
{
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    (callPackage ../packages/alcom.nix { }) # gui-v1.2.0-beta.3
    unityhub
    cudaPackages.cudatoolkit # nvcc + CUDA libraries for local work
  ];
}

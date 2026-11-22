# Hosts

One directory per machine. `flake.nix` builds every host through `mkHost`, which
provides three inputs:

| Input | File | Contents |
| --- | --- | --- |
| shared baseline | `modules/base.nix` | flakes, `nh` (`NH_FLAKE=/etc/nixos`) |
| hardware description | `hosts/<name>/hardware-configuration.nix` | committed, reviewed layout |
| host policy | `hosts/<name>/configuration.nix` | timezone, services, users, firewall |

All three hosts are live: `desu` (server, stable channel), `desktop` and `laptop`
(unstable). Each `hardware-configuration.nix` is committed with a deliberate
UEFI + btrfs subvolume layout - no `@docker`/`@lib` outside the server, LUKS on
the laptop, a shared ESP with Windows on the desktop - so treat these files as
reviewed config, not as raw generator output.

## Adding a host

1. Install the machine with the plain NixOS ISO.
2. Generate the hardware description into a scratch directory on the target
   machine, then diff it against the committed file:
   ```sh
   nixos-generate-config --root /mnt --dir /tmp/hw
   diff -u /tmp/hw/hardware-configuration.nix /etc/nixos/hosts/<name>/hardware-configuration.nix
   ```
   (`mkHost` imports `hosts/<name>/hardware-configuration.nix`; the flake is
   likewise evaluated from a checkout at `/etc/nixos`.) Never copy another
   host's hardware file: disk UUIDs and kernel modules differ. Do not paste the
   generator output over a committed file - it does not know about
   `neededForBoot`, the subvolume set, LUKS or `compress=`.

   On a machine that is not NixOS yet, the same command runs from a live ISO, or
   from any distro with Nix:
   ```sh
   nix shell nixpkgs#nixos-install-tools -c nixos-generate-config --show-hardware-config
   ```
   (`--show-hardware-config` prints and writes nothing. It reads the running
   machine's `/proc` and `/sys`, so it describes the machine it runs on - and it
   aborts on btrfs bind mounts such as a user-local `/nix/store`.)
3. Write `hosts/<name>/configuration.nix` with that machine's policy. Do not
   re-import `hardware-configuration.nix` or `modules/base.nix`; `mkHost` does.
4. Enable the output in `flake.nix` (note the full attribute path - `laptop = ...`
   at that spot would create a top-level `outputs.laptop`, not a NixOS config):
   ```nix
   nixosConfigurations.<name> = mkHost { hostName = "<name>"; };                    # nixos-unstable
   # nixosConfigurations.<name> = mkHost { hostName = "<name>"; channel = "stable"; };  # nixos-26.05
   ```
   Long-lived servers belong on `stable`; workstations stay on the default
   (unstable). The channel also selects the matching Home Manager release, so do
   not mix `channel = "stable"` with the unstable home-manager input.
5. Evaluate before deploying:
   ```sh
   nix eval .#nixosConfigurations.<name>.config.system.build.toplevel.drvPath
   sudo nh os switch   # NH_FLAKE=/etc/nixos, provided by modules/base.nix
   ```

Hosts that need extra modules (for example the server's disposable CI runners)
pass them through `mkHost { modules = [ ... ]; }` instead of editing the flake's
shared module list.

Graphical machines additionally import `modules/graphical.nix` in their
`configuration.nix`; it pulls in ghostty, the Nerd Font default and the
`home/graphical.nix` profile. Servers skip it and keep only `home/shared.nix`
(shell, prompt, git).

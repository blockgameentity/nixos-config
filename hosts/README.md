# Hosts

One directory per machine. `flake.nix` builds every host through `mkHost`, which
provides three inputs:

| Input | File | Contents |
| --- | --- | --- |
| shared baseline | `modules/base.nix` | flakes, `nh` (`NH_FLAKE=/etc/nixos`) |
| hardware description | `hosts/<name>/hardware-configuration.nix` | generated on the machine |
| host policy | `hosts/<name>/configuration.nix` | timezone, services, users, firewall |

`hosts/desu` is the deployed server. `hosts/laptop` and `hosts/desktop` are
skeletons whose flake outputs stay commented out until a real
`hardware-configuration.nix` exists.

## Adding a host

1. Install the machine with the plain NixOS ISO.
2. Generate the hardware description into this repo, on the target machine:
   ```sh
   nixos-generate-config --root /mnt --dir /etc/nixos/hosts/<name>
   ```
   (`mkHost` imports `hosts/<name>/hardware-configuration.nix`; the flake is
   likewise evaluated from a checkout at `/etc/nixos`.) Never copy another
   host's hardware file: disk UUIDs and kernel modules differ.
3. Write `hosts/<name>/configuration.nix` with that machine's policy. Do not
   re-import `hardware-configuration.nix` or `modules/base.nix`; `mkHost` does.
4. Enable the output in `flake.nix`:
   ```nix
   <name> = mkHost { hostName = "<name>"; };                    # nixos-unstable
   # <name> = mkHost { hostName = "<name>"; channel = "stable"; };  # nixos-26.05
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

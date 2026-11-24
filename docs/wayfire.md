# Wayfire session

Everything learned bringing Wayfire up on the CachyOS install of `desktop`, plus the NixOS
translation of it for **both workstations** (`desktop` and `laptop`). This lives on a branch on
purpose: Plasma is the known-good session, and if Wayfire does not earn its place this branch is
deleted rather than unpicked from `main`.

Two things are recorded here: the **defects** that made Wayfire feel broken (each with the upstream
reference behind it), and the **config** that is known to work — imported verbatim from the old
`~/.config` so it can be diffed rather than retyped.

State of the branch: the compositor **packages and builds** (see
[Packaging 0.11](#packaging-011-nixpkgs-is-behind)) and both hosts **evaluate**. What has not
happened yet is a real `nixos-rebuild switch` and a first boot into the session, so treat the
runtime checklist below as still outstanding.

## Why Wayfire at all

Plasma was kept only because it never failed at screensharing or Steam. Wayfire was preferred for
compositing but had exactly three complaints: screensharing, Steam focus/tray behaviour, and
graphical glitches on the portrait monitor. All three turned out to be diagnosable, and none of them
were "Wayfire is bad at this" — they were a stale plugin list, a duplicated portal service, and one
upstream bug that was already fixed in git but in no release.

## The five defects

### 1. Distorted windows on the portrait monitor

**Symptom**: graphic corruption on `HDMI-A-1`, the 1920x1080 panel rotated to `transform = 270`.
Worse with more windows open. Not present on the two unrotated outputs.

**Cause**: `wf::gles::render_target_aligned_orthographic_projection()` in `src/core/opengl.cpp`
built its projection from the *untransformed* buffer size, so any output with a 90/270 transform
got the wrong aspect ratio. Only plugins using that projection were affected — `blur` and `wobbly`.

**Evidence**:
- [Wayfire #3122 "Distorted Windows on Rotated / Transformed Displays"][i3122] — filed against
  `0.11.0-d3990237 (Jul 31 2026) branch makepkg wlroots-0.20.2`, i.e. the exact CachyOS package
  build installed here. `git log` of the `v0.11.0` tag confirms commit `d399023`.
- [PR #3171 "blur and wobbly: Fix for transformed outputs"][pr3171] — 8 lines, merged to `master`
  2026-10-24, no backport.
- Related: [#3161][i3161] "Desktop area wrong on a rotated 1080p screen", [#3173][i3173] "Vertical
  misalignment between rotated 1080p and normal 4k screen".

**Fix**: `patches/wayfire-3171-transformed-outputs.patch`, applied to a `v0.11.0` tree. The patch
swaps width/height when `target.wl_transform & 1` (odd transforms are the 90/270 ones).

**Beware**: the latest wayfire tag is still `v0.11.0`, so **no release contains this fix**. Check
whether the version being packaged already has it before carrying the patch — see
[Open questions](#open-questions).

### 2. Screensharing hangs, black frames, or no picker

**Symptom**: screenshare from Firefox/Chromium/OBS works intermittently or not at all.

**Cause**: two competing ways to start the same service. Wayfire 0.11.0's *shipped* `wayfire.ini`
contains `portal = /usr/libexec/xdg-desktop-portal` under `[autostart]` ("Needed by some GTK
applications"), while the wiki's screencast recipe — which was also pasted in — adds
`xdp = sleep 1 && systemctl --user restart xdg-desktop-portal xdg-desktop-portal-wlr`. The first
launches a second portal frontend as a child of the compositor; the second restarts the
systemd-activated one. They race for `org.freedesktop.portal.Desktop`.

When the frontend cannot resolve the desktop it falls back to `default=*`, and with
`xdg-desktop-portal-kde` installed (it is, on a Plasma machine) the KDE `ScreenCast` backend gets
picked — which requires KWin and fails on any wlroots compositor.

**Fix**: drop the `portal =` autostart line, keep the wiki's `xdp` restart. The manual launch was
redundant anyway: `0_env = dbus-update-activation-environment --systemd ...` already hands
`WAYLAND_DISPLAY`/`XDG_CURRENT_DESKTOP` to D-Bus *and* systemd user services, which is the actual
fix for the GTK startup problem `portal =` was there for.

The rest of the chain is correct and worth keeping:
- `wayfire` ships `/usr/share/xdg-desktop-portal/wayfire-portals.conf` with `default=wlr;*`.
- `~/.config/xdg-desktop-portal-wlr/config` with `chooser_type=simple` + a chooser command.
  On CachyOS that was `wf-stream-chooser` (from `wf-shell`); **nixpkgs has no `wf-shell`**, so the
  NixOS branch uses upstream's own documented invocation instead:
  `slurp -f 'Monitor: %o' -or` — you click the screen you want to share. This is wired through
  `xdg.portal.wlr.settings.screencast` in `modules/wayfire.nix`, not a hand-written config file.
- There is no `screencopy` plugin to enable — `wlr-screencopy` is core (`wlr_screencopy_manager_v1_create`
  is linked into the wayfire binary).

**Unverified**: `max_fps = 60` against a 240 Hz panel is untested for tearing/latency trade-offs.

### 3. Steam: windows behind, no focus, tray clicks doing nothing

**Symptom**: Friends & Chat opens *under* the main window, popup menus appear to do nothing, tray
clicks do not raise anything.

**Cause**: `xdg-activation` was missing from `core.plugins`. Steam is XWayland; every "open this
already-running window" request from a tray item, notification or chat is an activation request, and
without that protocol the compositor has nothing to grant it with. Wayfire's own wiki has a section
for this: *"Apps are not focused when expected — you need to enable the XDG Activation protocol
plugin."*

**Evidence**: [#1859 "Several problems with Steam"][i1859] is close to verbatim; note the maintainer
could only reproduce it **with multiple outputs**, and that the menu bug reliably appears after
dragging Steam to another output ("maybe the menu is appearing somewhere else than on-screen
position"). [#1881][i1881] is the same class: Steam not visible in a multi-output setup when it
opens on another output. A single monitor was never enough to reproduce.

**Fix**: `xdg-activation` added to `core.plugins`. Left `workarounds.focus_main_surface_instead_of_popup`
off — upstream documents it as a Qt copy/paste workaround, not a Steam one.

### 4. ironbar duplicates the bars when a monitor is replugged

**Symptom**: after unplugging and replugging the third monitor (done before every VR session — a
4090 cannot hold four EDIDs while the Index is attached), bars duplicate and misbehave.

**Cause**: [#1671 "Duplicate bars after monitor power cycle"][ib1671]. The invisible autohide
"hotspot" layer surface was not destroyed when the bar was, so after an output teardown the old
hotspot survived and the next hover/scroll at the edge spawned a second bar over it. Fixed in
[#1672][ib1672] — five lines, `hotspot_window.close(); hotspot_window.destroy();` in `Bar::close`.

Why this machine specifically: hotspot windows only exist on **autohide** bars, and only the
`[monitors.DP-1]` block uses `autohide = 2000`. On top of that, `swayidle` was destroying and
recreating the DP-1 output every idle cycle (`wlr-randr --output DP-1 --off`), and `outputs.sh`
cycles DP-2 and HDMI-A-1 off/on at every login for the NVIDIA DSC head staging — three hotplug
events during bar startup, hence "sometimes".

**Fix**: three parts.
1. Build ironbar from master (the fix is in no release — `v0.19.1` shipped 2026-09-20, the fix
   landed 2026-10-28). Note the 0.20.0-pre **split**: master now builds a daemon called `ironbard`
   plus an `ironbar` CLI, so autostart had to point at `ironbard`
   (`a745ccf "refactor: split cli/ipc types into separate crates"`, 2026-11-02).
2. `wlopm --off/--on DP-1` instead of `wlr-randr --off/--on`: `wlopm` goes through
   `wlr-output-power-management`, which keeps the output object alive. No teardown, no bar rebuild,
   and the OLED never drops from 240 Hz (the old `--off/--on` made Wayfire re-apply the
   `[output:DP-1]` bootstrap mode, silently losing 75 Hz every idle cycle).
3. Run `outputs.sh` *before* ironbar starts, not in parallel with it.

Live escape hatch for real unplugs: `ironbar reload` (or `ironbard reload`) drops duplicates without
restarting anything.

### 5. Losing windows when the displays sleep, or when the last output disappears

**Symptom**: everything appears gone after monitors sleep or the GPU drops outputs — "the session
ended".

**Cause**: two separate things, and the session is usually *still alive*.
- Wayfire never exits for lack of outputs. It creates a virtual `NOOP-1` output:
  *"Wayfire generally assumes that an enabled output is always available … when switching
  connectors it might happen that temporarily no output is available. For those cases, we create a
  virtual output with the noop backend"* (`src/core/output-layout.cpp`). Views on a removed output
  are then transferred to the active output (`transfer_views`), which may be `NOOP-1`.
- Nothing moves those views back when the real outputs return. That is exactly what the
  `preserve-output` plugin exists for, and the wiki states the failure mode precisely:
  *"Some monitors and/or GPUs disconnect the outputs during DPMS, which can result in all of your
  windows ending up on one output after waking them from sleep. This plugin prevents that from
  happening."*

**Fix**: `preserve-output` added to `core.plugins`, plus the `wlopm` change above so DPMS no longer
destroys the output at all.

**One genuine exit path exists**: if render init for the noop output fails,
`ensure_noop_output()` logs `failed to init wlr render for noop output!` and calls
`std::exit(0)`. That kills the compositor and every client. If a session dies outright, this is the
first thing to look for in the log. It was **not** observed here — `coredumpctl` had no wayfire
entries, though its history on the old install only went back a day.

## The stale-plugin-list lesson

Almost every option value in the old `wayfire.ini` was a stock default. What had drifted was the
one hand-maintained line, `core.plugins`:

| entry | state |
| --- | --- |
| `xdg-activation` | real plugin, **missing** — caused defect 3 |
| `preserve-output` | real plugin, **missing** — caused defect 5 |
| `workarounds` | **not a plugin in 0.11** — its options are registered by core; listing it made Wayfire log a plugin-load error every startup |

After cleanup all 26 entries resolve to a real `/usr/lib/wayfire/lib<name>.so`. Worth re-checking on
every major compositor bump: the plugin set is the only part of the config that has to be
maintained by hand, and a missing entry fails silently (a dead entry logs and continues).

## Display ownership model

Three things wanted to own output state: `wayfire.ini` (`[output:*]` sections), `outputs.sh`
(wlr-randr), and `swayidle`. They now have strictly separate jobs:

- **`wayfire.ini`** only holds a safe bootstrap mode. `workarounds.use_external_output_configuration = true`
  makes Wayfire stop applying its own output options once an external client has configured them.
- **`outputs.sh`** owns the real layout. It exists because NVIDIA 620 refuses the direct
  all-at-once transition to the AW3425DW's DSC-backed 3440x1440@240 mode but accepts a staged
  sequence — free the display heads, bring DP-1 up alone at 240 Hz, then add DP-2 and HDMI-A-1 one
  at a time, with a `restore_known_good` fallback on failure.
- **`swayidle`** now uses `wlopm` (DPMS), so it never removes an output.

## Packaging 0.11 (nixpkgs is behind)

0.10.1 would not do: 0.11 replaced the blur renderer, moved to wlroots 0.20 and restructured the
plugin/protocol layout, the config here was generated by 0.11, and three of the five defects above
are 0.11 behaviour. So the branch builds 0.11 itself.

What nixpkgs has, checked directly rather than via a channel alias:

| source | wayfire |
| --- | --- |
| `nixos-unstable` branch HEAD | 0.10.1 |
| `master` branch HEAD | 0.10.1 |
| [NixOS/nixpkgs PR #492535][np492535] "wayfire: update ecosystem to 0.11.0" | **open since 2026-10-24** |

`packages/wayfire.nix` overrides the nixpkgs derivation instead of copying it, so `postPatch`, the
`--sysconfdir` and `providedSessions` keep tracking nixpkgs. Three things actually had to change
beyond the version:

1. **wlroots `0.19` → `wlroots_0_20`.** 0.11 requires it; nixpkgs already carries `wlroots_0_20`
   (0.20.2).
2. **wf-config from the submodule, not nixpkgs.** nixpkgs has `wf-config` 0.10.0; 0.11 wants 0.11.
   Rather than package a second wf-config for this branch, the v0.11.0 tag's own pinned submodule is
   built (`-Duse_system_wfconfig=disabled`) and nixpkgs' 0.10 input is removed from the closure so
   two `libwf-config.so` can never be in play. It installs as `lib/libwf-config.so.1` alongside the
   compositor.
3. **Two build fixes.** The wf-config subproject needs `glm` headers (nixpkgs' 0.10 build linked a
   system wf-config that resolved GLM itself), and `libdrm`'s headers include each other by bare name
   (`xf86drmMode.h` pulls in `drm.h`), so `NIX_CFLAGS_COMPILE` adds `libdrm/include/libdrm`.
   Subproject unit tests are switched off: they pull doctest, which nixpkgs only ships for
   `checkPhase`.

**Verified by building it** (`nix build` against nixpkgs-unstable, x86_64-linux): the derivation
succeeds, and the output carries the plugins this config needs — `xdg-activation`, `preserve-output`,
`blur`, `foreign-toplevel`, `ipc`, `simple-tile` and the rest — plus
`share/wayland-sessions/wayfire.desktop`, `share/xdg-desktop-portal/wayfire-portals.conf` and
`lib/libwf-config.so.1`. `libwinshadows.so` is correctly absent (separate extras tree).

**When #492535 lands**, delete `packages/wayfire.nix`, switch `modules/wayfire.nix` back to
`pkgs.wayfire`, and re-check whether the patch is still needed — it targets `v0.11.0` source, so it
may not apply to a newer tag unbent.

## What is in this branch

| path | what it is |
| --- | --- |
| `docs/wayfire.md` | this file |
| `packages/wayfire.nix` | wayfire **0.11.0**, built from upstream with PR #3171 applied |
| `patches/wayfire-3171-transformed-outputs.patch` | upstream fix for defect 1 |
| `home/files/wayfire/wayfire.ini` | the working config, from the CachyOS install (deviations listed below) |
| `home/files/wayfire/scripts/` | `outputs.sh` (DSC staging), `clipboard.sh`, `wallpaper.sh`, `slideshow.sh` |
| `home/files/ironbar/config.toml`, `style.css` | the bar, including the per-monitor autohide block |
| `home/wayfire.nix` | writes the above into `~/.config` |
| `modules/wayfire.nix` | compositor package, display manager, portals, session tooling |

### Deviations from the CachyOS config

Only what could not survive the move:

- `[autostart] panel=` runs `ironbar` from `PATH` instead of `~/.cargo/bin/ironbard` (that was a cargo
  build of 0.20.0-pre; nixpkgs ships 0.19.1, whose daemon is still called `ironbar`).
- `winshadows`, `focus-request` and `focus-steal-prevent` are removed from `core.plugins`. All three
  live in the separate `wayfire-plugins-extra` tree, which nixpkgs only carries for 0.10.1
  (`wayfirePlugins.*` are built against it, so using them with a 0.11 core is an ABI mismatch).
  Upstream does tag extras for 0.11 (`v0.11.2`) — see "Still outstanding" for what packaging them
  takes. Worth knowing: on CachyOS these were already suspect, because the distro's
  `wayfire-plugins-extra` is 0.10.0 running against a 0.11 core.
- `command_lock` and the `swayidle` timeout both call `swaylock -f -c 000000`. The CachyOS value
  was `-c 000000c` — seven hex digits, which swaylock rejects (`parse_color` accepts only 6 or 8)
  and replaces with opaque white `0xFFFFFFFF`. That is why the lockscreen came up white instead of
  black. Five-sixths of the value was right; the trailing `c` was the whole bug.
- `[autostart] session = systemctl --user start graphical-session.target`. Not in the CachyOS config
  because CachyOS started the portal from a plasma session that had already started that target.
  Upstream's `xdg-desktop-portal.service` has `Requisite=graphical-session.target`, so on Wayfire
  every portal activation failed with `start failed with result 'dependency'`: no Settings portal,
  no screencast, and GTK logging "Gdk cannot get portal org.freedesktop.portal.settings".
- `ironbar`'s `[launcher]` block sets `type = "gtk"`. The launcher widget is a front-end with no
  default backend, so the button rendered and clicked into nothing. `walker` is the alternative if
  reusing the Super+X launcher is preferred; ironbar would then talk to the already-running daemon.
- Nothing else. Output sections, keybinds, blur, workspace layout and the ironbar config are as
  they were.

Not committed: `wayfire-scripts/wallpaper.png` (8.3 MiB) and `wallpapers/` (13 MiB) — they are
selection state, not config. Point `wallpaper.sh` at a real path after the first boot.

`home/files/wayfire/wayfire.ini` is installed as a read-only symlink into the Nix store. That is
deliberate (the repo is the source of truth) and means saving settings from `wcm` will not persist —
edit the repo instead. If in-place editing is wanted later, switch that one file to
`home.activation` copy semantics.

## Verification checklist

Run these inside the Wayfire session, in this order.

```sh
# 1. compositor + patch actually in use
wayfire --version                    # expect a build newer than 0.11.0-d399023
# 2. exactly one portal frontend, and the wlr backend chosen
ps -eo args | grep -c '[x]dg-desktop-portal$'          # must print 1
journalctl --user -b -u xdg-desktop-portal | grep -iE 'wlr|kde'
systemctl --user show-environment | grep -E '^(WAYLAND_DISPLAY|XDG_RUNTIME_DIR|XDG_CURRENT_DESKTOP)'
# 3. screencast backend is live
gdbus call --session --dest org.freedesktop.portal.Desktop \
  --object-path /org/freedesktop/portal/desktop \
  --method org.freedesktop.DBus.Properties.Get \
  org.freedesktop.portal.ScreenCast version
# 4. output power management (wlopm) is advertised
wlopm                                             # lists outputs instead of erroring
# 5. plugins all load
journalctl --user -b | grep -i "error loading plugin"   # expect no output
# 6. the noop-exit path never fired
journalctl --user -b | grep -i "noop"                   # expect no fatal render init error
```

Behavioural tests: drag a blurred window across the portrait monitor (defect 1); share a screen in
Firefox (defect 2); click a Steam tray item and Friends & Chat (defect 3); power-cycle the OLED
(defect 4); unplug the third monitor and replug it, then idle past the DPMS timeout (defects 4+5).

## Still outstanding

Both hosts evaluate against nixpkgs-unstable with this module in place, and the compositor package
builds. What is *not* done: a real `nixos-rebuild switch`, a first boot into the session, and the
runtime checklist above. Per item:

1. **ironbar version.** nixpkgs ships **0.19.1**, which still has defect 4 and still names its binary
   `ironbar` (the 0.20 split into `ironbard` + CLI happened after 0.19.1). So the bar runs today with
   the duplicate-bar bug, mitigated by `wlopm` and the autostart ordering, and
   `ironbar reload` as the live fix. When nixpkgs picks up 0.20+, update the `[autostart] panel=`
   line in `home/files/wayfire/wayfire.ini` to `ironbard`.
2. **NVIDIA on NixOS.** `scripts/outputs.sh` encodes a workaround for the *620 series* driver's DSC
   handling on the AW3425DW. NixOS pins its own driver version; re-test the staged sequence before
   trusting it. The script already refuses to run on a machine without that panel, which is what
   keeps it a no-op on the laptop — so if the staging turns out not to be needed, `outputs.sh` can be
   dropped entirely and the layout left to Wayfire.
3. **`wayfire-plugins-extra` is not packaged** (`winshadows`, `focus-request`,
   `focus-steal-prevent`, `annotate`, `mag`, `view-shot`, `pixdecor`, `filters`). Upstream has
   `v0.11.2`; the cost is that this tree pulls its plugins as meson **wraps** (`.wrap` files
   pointing at separate repos) rather than submodules, so a sandboxed build needs each wrap target
   fetched and pre-unpacked into `subprojects/` before configure. Two derivations
   (`wayfire-shadows`, `focus-request`) would restore everything this config asks for.
4. **`wayfire.ini` is read-only.** It is a symlink into the store, so `wcm` saves will not persist.
   Edit the repo instead; switch to `home.activation` copy semantics if in-place editing is wanted.
5. **Wallpapers.** `wayfire.png` and `wallpapers/` are deliberately not in the repo (21 MiB of
   selection state). Drop them in `~/.local/share/wayfire/` after the first boot — `wallpaper.sh` and
   `slideshow.sh` look there first.

## References

- [Wayfire wiki: Tips & Tricks — Screen sharing][wfscreen], [Apps are not focused when expected][wffocus]
- [Wayfire wiki: Configuration — preserve-output][wfpreserve], [xdg-activation][wfxdg]
- [#3122][i3122], [PR #3171][pr3171], [#3161][i3161], [#3173][i3173], [#1859][i1859], [#1881][i1881]
- ironbar [#1671][ib1671], [PR #1672][ib1672], [#1196][ib1196] (older stale-bar bug, fixed in 0.19.0)

[i3122]: https://github.com/WayfireWM/wayfire/issues/3122
[np492535]: https://github.com/NixOS/nixpkgs/pull/492535
[pr3171]: https://github.com/WayfireWM/wayfire/pull/3171
[i3161]: https://github.com/WayfireWM/wayfire/issues/3161
[i3173]: https://github.com/WayfireWM/wayfire/issues/3173
[i1859]: https://github.com/WayfireWM/wayfire/issues/1859
[i1881]: https://github.com/WayfireWM/wayfire/issues/1881
[ib1671]: https://github.com/JakeStanger/ironbar/issues/1671
[ib1672]: https://github.com/JakeStanger/ironbar/pull/1672
[ib1196]: https://github.com/JakeStanger/ironbar/issues/1196
[wfscreen]: https://github.com/WayfireWM/wayfire/wiki/Tips-%26-Tricks#screen-sharing
[wffocus]: https://github.com/WayfireWM/wayfire/wiki/Tips-%26-Tricks#apps-are-not-focused-when-expected
[wfpreserve]: https://github.com/WayfireWM/wayfire/wiki/Configuration#preserve-output
[wfxdg]: https://github.com/WayfireWM/wayfire/wiki/Configuration#xdg-activation-protocol

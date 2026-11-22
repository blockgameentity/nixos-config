# Shared btrfs handling for hosts that keep their filesystems in subvolumes.
#
# The mount table itself (which subvolume is mounted where, with which options,
# and which of them use `neededForBoot`) lives in
# hosts/<name>/hardware-configuration.nix: it is per machine and its devices
# differ. This module owns only the host-independent housekeeping.
{ config, lib, ... }:
let
  cfg = config.desu.btrfs;
in {
  options.desu.btrfs = {
    enable = lib.mkEnableOption "btrfs housekeeping (scrub and trim)";

    scrubInterval = lib.mkOption {
      type = lib.types.str;
      default = "monthly";
      description = ''
        systemd calendar spec for `btrfs scrub`. Scrubbing verifies checksums and
        reports (rather than silently repairing) corruption, so it is the early
        warning for a failing disk.
      '';
    };

    scrubMounts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "/" ];
      description = ''
        Leave empty to scrub every btrfs filesystem found in `fileSystems`: the
        upstream module deduplicates by device, which is what scrub operates on,
        so all subvolumes of one device are covered by a single mountpoint. Only
        set this to override that, e.g. to leave a scratch disk unscrubbed.
      '';
    };

    trim = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Weekly `fstrim` instead of mount option `discard`. Continuous discard
        has a measurable cost on btrfs; a timer is the recommended tradeoff.
        Turn this off if a device ignores TRIM anyway (some USB/RAID setups).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # / is btrfs: without this the module is only pulled in late, after the
    # stage-1 mount attempt.
    boot.initrd.supportedFilesystems = [ "btrfs" ];

    services.btrfs.autoScrub = {
      enable = true;
      interval = cfg.scrubInterval;
      fileSystems = lib.mkIf (cfg.scrubMounts != [ ]) cfg.scrubMounts;
    };

    services.fstrim.enable = cfg.trim;
  };
}

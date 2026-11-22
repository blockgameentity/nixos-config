{ config, lib, pkgs, ... }:
let
  cfg = config.services.trustedMacRunner;
  settings = (pkgs.formats.json {}).generate "mac-runner.json" {
    inherit (cfg) repository tokenFile ttlSeconds;
    stateDir = "/Users/ci/ci-runner";
    runner = "${pkgs.github-runner}/bin/Runner.Listener";
  };
in {
  options.services.trustedMacRunner = {
    enable = lib.mkEnableOption "trusted-only Apple Silicon runner";

    repository = lib.mkOption { type = lib.types.strMatching "[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+"; default = "ExamWatcher/desktop"; };
    tokenFile = lib.mkOption { type = lib.types.str; default = "/Users/ci/.config/github-runner-token"; };
    ttlSeconds = lib.mkOption { type = lib.types.ints.positive; default = 7200; };
    trustedRegistrationConfirmed = lib.mkOption {
      type = lib.types.bool; default = false;
      description = "Confirm runner registration is restricted to trusted workflows, not merely by labels";
    };
  };
  config = {
    nixpkgs.hostPlatform = "aarch64-darwin";
    system.stateVersion = 6;
    nix.settings.experimental-features = [ "nix-command" "flakes" ];
    environment.systemPackages = with pkgs; [ git curl jq python3 rustup bun ];
    users.knownUsers = [ "ci" ];
    users.users.ci = {
      name = "ci";
      uid = 503;
      home = "/Users/ci";
      shell = "/bin/bash";
    };
    system.activationScripts.ciRunner.text = lib.mkIf cfg.enable ''
      install -d -m 0700 -o ci -g staff /Users/ci
      install -d -m 0700 -o ci -g staff /Users/ci/ci-runner
      install -d -m 0700 -o ci -g staff /Users/ci/.config
    '';
    assertions = [{ assertion = !cfg.enable || cfg.trustedRegistrationConfirmed;
      message = "Mac runners are NOT sandboxed. Restrict repository/workflow authorization before enabling.";
    }];
    launchd.daemons.ci-runner = lib.mkIf cfg.enable {
      path = [ pkgs.bash pkgs.coreutils pkgs.git pkgs.curl pkgs.rustup pkgs.bun "/usr/bin" "/bin" "/usr/sbin" "/sbin" ];
      serviceConfig = {
        ProgramArguments = [ "${pkgs.python3}/bin/python3" "${../../ci}/mac.py" (toString settings) ];
        UserName = "ci";
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 60;
        ProcessType = "Background";
        StandardOutPath = "/Users/ci/ci-runner.log";
        StandardErrorPath = "/Users/ci/ci-runner-error.log";
      };
    };
  };
}

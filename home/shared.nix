# Universal home profile: everything that is identical on the server, laptop and
# desktop. Imported by modules/base.nix for the primary account.
#
# Graphical-only pieces (ghostty, fonts) live in home/graphical.nix, which only
# machines that import modules/graphical.nix pull in.
{
  pkgs,
  ...
}: {
  # First Home Manager generation for this configuration; bump only for a
  # deliberate migration, never implicitly.
  home.stateVersion = "26.05";

  # fish is the interactive shell on every host: the desktop already logs into
  # fish, so the server follows instead of keeping a second shell vocabulary.
  programs.fish = {
    enable = true;
    # Same interactive behaviour as the old ~/.config/fish/config.fish: no
    # greeting text, pfetch instead of the old catnap fetch.
    interactiveShellInit = ''
      set -g fish_greeting
      pfetch
    '';
    shellAliases = {
      cat = "bat";
      du = "dust";
      ls = "eza --icons -a -G -l --color=always --group-directories-first";
    };
  };

  programs.starship = {
    enable = true;
    enableFishIntegration = true;
  };
  # The prompt config is copied verbatim from ~/.config/starship.toml, so it can
  # still be edited/diffed as plain TOML instead of a Nix attrset.
  xdg.configFile."starship.toml".source = ./files/starship.toml;

  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
  };

  programs.fzf = {
    enable = true;
    enableFishIntegration = true;
  };

  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "desu";
        email = "git@desu.re";
      };
      init.defaultBranch = "main";
    };
  };
  # programs.gh also registers the `gh auth git-credential` helper for
  # github.com and gist.github.com; on a new machine run `gh auth login` once
  # (the token is a secret and never lives in this repo; gh keeps it in the
  # keyring / hosts.yml, which stay writable).
  #
  # config.yml is a read-only store symlink, so anything `gh auth login` would
  # write there ("open .../config.yml: read-only file system") has to be
  # declared here instead.
  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "https";
      # gh waits for its browser command to exit before it starts polling for
      # the token. xdg-open runs Firefox in the foreground when no Firefox is
      # open yet, so `gh auth login` hung until the whole browser was closed
      # (and Firefox's stderr, e.g. "[GFX1-]: Decoder missing TFI", landed in
      # the terminal). Detach it so gh returns immediately.
      browser = "${pkgs.writeShellScript "gh-browser" ''
        ${pkgs.util-linux}/bin/setsid -f ${pkgs.xdg-utils}/bin/xdg-open "$@" >/dev/null 2>&1
      ''}";
    };
  };

  # delta pages git diff/log/blame through a syntax-highlighting viewer;
  # enableGitIntegration wires core.pager, interactive.diffFilter and pager.blame
  # into the git config generated above.
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true;
      line-numbers = true;
      side-by-side = true;
      syntax-theme = "gruvbox-dark";
    };
  };

  # lazygit: TUI git client, available as `lg`. Nerd Fonts v3 icons only render
  # where a Nerd Font is active (graphical profile installs one).
  programs.lazygit = {
    enable = true;
    settings.gui.nerdFontsVersion = "3";
  };

  # direnv + nix-direnv: `use flake` in a .envrc loads the project devShell.
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    enableFishIntegration = true;
  };

  programs.btop.enable = true;

  # Helix is the only terminal editor on every host: gruvbox_dark_hard to match
  # the ghostty theme, nothing else configured. No vim/vis/nvim here by design -
  # the graphical editor is zed (home/graphical.nix).
  programs.helix = {
    enable = true;
    settings.editor.theme = "gruvbox_dark_hard";
  };

  # Same SSH aliases on every host. Only aliases and directives live here - key
  # material stays on each machine, and host-specific addresses can be added per
  # host later without touching this block.
  programs.ssh = {
    enable = true;
    # Declare the globals explicitly instead of relying on the deprecated
    # enableDefaultConfig defaults (ControlMaster multiplexing on by default).
    enableDefaultConfig = false;
    settings = {
      github = {
        HostName = "github.com";
        User = "git";
      };
      gist = {
        HostName = "gist.github.com";
        User = "git";
      };
      "*" = {
        AddKeysToAgent = "yes";
        ForwardAgent = false;
        HashKnownHosts = false;
        UserKnownHostsFile = "~/.ssh/known_hosts";
        ServerAliveInterval = 60;
        ServerAliveCountMax = 3;
        ControlMaster = "auto";
        ControlPath = "~/.ssh/master-%r@%n:%p";
        ControlPersist = "10m";
      };
    };
  };

  # Cargo: sccache as the compiler wrapper plus mold as the linker, so Rust
  # builds reuse the cache and link fast on every host. `pkgs.mold` ships
  # bin/ld.mold, which is exactly what `-fuse-ld=mold` resolves in PATH.
  home.file.".cargo/config.toml".text = ''
    [build]
    rustc-wrapper = "sccache"

    [target.x86_64-unknown-linux-gnu]
    rustflags = ["-C", "link-arg=-fuse-ld=mold"]
  '';

  home.sessionVariables = {
    EDITOR = "hx";
    VISUAL = "hx";
  };

  home.packages = with pkgs; [
    pfetch-rs # replaces catnap
    eza
    bat
    dust
    ripgrep
    fd
    jq
    # Language/toolchain basics used on every machine, server included.
    cargo
    sccache # cargo rustc-wrapper, see ~/.cargo/config.toml below
    mold # cargo linker, see ~/.cargo/config.toml below
    ruff
    bun
    uv
    go
    # General CLI tools.
    act # run GitHub Actions locally
    pandoc
    android-tools # adb
    scrcpy
    croc
    dog # DNS client
    imagemagick
    ipinfo # ipinfo-cli
    iperf3
    fend # TUI calculator
    yazi # TUI file manager (also on the server)
    yt-dlp
    typst
    zstd
    kondo # project build-artifact cleaner
    ffmpeg
    radare2 # r2
  ];
}

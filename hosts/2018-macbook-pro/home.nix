{ username, pkgs, ... }:
let
in
{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = username;
  home.homeDirectory = "/Users/${username}";

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "23.05"; # Please read the comment before changing.

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = [
    pkgs.nerd-fonts.jetbrains-mono

    pkgs.btop
    pkgs.curl
    pkgs.delta
    pkgs.dust
    pkgs.eza
    pkgs.fd
    pkgs.ffmpeg
    pkgs.fzf
    pkgs.inetutils
    pkgs.jq
    pkgs.just
    pkgs.nmap
    pkgs.ripgrep
    pkgs.sd
    pkgs.tldr
    pkgs.zoxide

    (pkgs.writeShellScriptBin "capture.zsh"
      (pkgs.fetchFromGitHub
        {
          owner = "Valodim";
          repo = "zsh-capture-completion";
          rev = "740fce754393513d57408bc585fde14e4404ba5a";
          sha256 = "ZfIYwSX5lW/sh0dU13BUXR4nh4m9ozsIgC5oNl8LaBw=";
        } + "/capture.zsh")
    )
  ];

  home.sessionVariables = {
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  programs.bat = {
    enable = true;
    themes = {
      "Catppuccin Mocha" = {
        src = pkgs.catppuccin.override { variant = "mocha"; themeList = [ "bat" ]; };
        file = "bat/Catppuccin Mocha.tmTheme";
      };
    };
  };

  programs.git = {
    enable = true;
    signing.format = null;

    settings = {
      user.name = "Cyril Ledru";
      user.email = "cyril@lev-art.com";

      branch = {
        sort = "committerdate";
      };
      color = {
        ui = true;
      };
      column = {
        ui = "auto";
      };
      commit = {
        verbose = true;
      };
      core = {
        editor = "vim";
        ignorecase = false;
        pager = "delta";
      };
      credential = {
        helper = "osxkeychain";
      };
      delta = {
        navigate = true;
        syntax-theme = "Catppuccin Mocha";
        line-numbers = true;
        side-by-side = false;
        keep-plus-minus-markers = true;
      };
      diff = {
        algorithm = "histogram";
        colorMoved = "default";
        mnemonicPrefix = true;
        renames = true;
        wsErrorHighlight = "all";
      };
      fetch = {
        prune = true;
        pruneTags = true;
        all = true;
      };
      help = {
        autocorrect = "prompt";
      };
      init = {
        defaultBranch = "master";
      };
      interactive = {
        diffFilter = "delta --color-only";
      };
      merge = {
        tool = "vimdiff";
        conflictStyle = "zdiff3";
      };
      mergetool = {
        keepBackup = false;
        prompt = false;
      };
      pull = {
        ff = "only";
      };
      push = {
        default = "simple";
        autoSetupRemote = true;
      };
      rebase = {
        autoSquash = true;
        updateRefs = true;
      };
      rerere = {
        enabled = true;
        autoUpdate = true;
      };
      tag = {
        sort = "version:refname";
      };
    };

    lfs.enable = true;

    ignores = [
      ".idea"
      "*.iml"
      ".DS_Store"
      "venv"
      ".vscode"
      ".venv"
    ];
  };

  programs.ghostty = {
    enable = true;
    package = null;
    enableZshIntegration = true;
    settings = {
      theme = "Catppuccin Mocha";
      desktop-notifications = true;
      keybind = "option+backspace=text:\\x1b\\x7f";
      macos-option-as-alt = true;
    };
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    shellAliases = {
      cat = "bat --plain";
      ls = "eza";
      ll = "eza -l";
      la = "eza -la";
      tree = "eza --tree";
      find = "fd";
      du = "dust";
      top = "btop";
    };

    history.share = false;

    sessionVariables = {
      LANG = "en_US.UTF-8";
      LESS = "--no-init --quit-if-one-screen -R";
    };

    envExtra = ''
      # See https://discourse.nixos.org/t/why-can-i-not-execute-a-new-version-of-nix-with-nix-shell/31032
      [[ ! $(command -v nix) && -e "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]] && source "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
    '';

    initContent = ''
      eval "$(/usr/local/bin/brew shellenv)"
      eval "$(zoxide init zsh)"
    '';

    oh-my-zsh = {
      enable = true;
      theme = "af-magic";
      plugins = [ "aliases" "git" ];
    };
  };
}

{ config, lib, pkgs, pkgs-azure, ... }:
let
  username = "cyrilledru";
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
    # # Adds the 'hello' command to your environment. It prints a friendly
    # # "Hello, world!" when run.
    # pkgs.hello

    # # It is sometimes useful to fine-tune packages, for example, by applying
    # # overrides. You can do that directly here, just don't forget the
    pkgs.nerd-fonts.jetbrains-mono

    # # You can also create simple shell scripts directly inside your
    # # configuration. For example, this adds a command 'my-hello' to your
    # # environment:
    # (pkgs.writeShellScriptBin "my-hello" ''
    #   echo "Hello, ${config.home.username}!"
    # '')

    (pkgs-azure.azure-cli.withExtensions [ pkgs-azure.azure-cli.extensions.quota ])
    # bat installed via programs.bat below
    pkgs.btop
    pkgs.circleci-cli
    pkgs.curl
    pkgs.delta
    pkgs.dust
    pkgs.eza
    pkgs.fd
    pkgs.ffmpeg
    pkgs.fzf
    pkgs.google-cloud-sdk
    pkgs.inetutils
    pkgs.jq
    pkgs.just
    pkgs.lastpass-cli
    pkgs.ngrok
    pkgs.nil
    pkgs.nixpkgs-fmt
    pkgs.nmap
    pkgs.pipx
    pkgs.ripgrep
    pkgs.sd
    pkgs.ssm-session-manager-plugin
    pkgs.terraform
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

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    # # Building this configuration will create a copy of 'dotfiles/screenrc' in
    # # the Nix store. Activating the configuration will then make '~/.screenrc' a
    # # symlink to the Nix store copy.
    # ".screenrc".source = dotfiles/screenrc;

    # # You can also set the file content immediately.
    # ".gradle/gradle.properties".text = ''
    #   org.gradle.console=verbose
    #   org.gradle.daemon.idletimeout=3600000
    # '';

    # This does not work well with docker, because it creates a symlink which cannot be bind-mounted.
    # ".aws/config".source = dotfiles/aws/config;
    ".oh-my-zsh-custom".source = dotfiles/oh-my-zsh;
    ".config/mise/config.toml".source = dotfiles/mise/config.toml;
    ".config/karabiner".source = config.lib.file.mkOutOfStoreSymlink
      "/Users/cyrilledru/Tech/nix-config/hosts/2023-macbook-pro/dotfiles/karabiner";
  };

  # You can also manage environment variables but you will have to manually
  # source
  #
  #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  /etc/profiles/per-user/cyrilledru/etc/profile.d/hm-session-vars.sh
  #
  # if you don't want to manage your shell through Home Manager.
  home.sessionVariables = {
    # EDITOR = "emacs";
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
        tool = "p4merge";
        conflictStyle = "zdiff3";
      };
      mergetool = {
        keepBackup = false;
        prompt = false;
        p4merge = {
          cmd = "p4merge \"$BASE\" \"$LOCAL\" \"$REMOTE\" \"$MERGED\"";
          keepTemporaries = false;
          trustExitCode = false;
        };
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

  programs.gh = {
    enable = true;

    settings = {
      git_protocol = "https";
      prompt = "enabled";

      aliases = {
        co = "pr checkout";
        cw = "!git push -u origin HEAD && gh pr create -w";
        cof = "!id=\"$(gh pr list -L100 | fzf | cut -f1)\"; [ -n \"$id\" ] && gh pr checkout \"$id\"";
      };
    };
  };

  programs.tmux = {
    aggressiveResize = true;
    baseIndex = 1;
    clock24 = true;
    enable = true;
    historyLimit = 100000;
    mouse = true;
    keyMode = "vi";
    plugins = with pkgs.tmuxPlugins; [
      {
        plugin = catppuccin;
        extraConfig = ''
          set -g @catppuccin_flavor "mocha"
          set -g @catppuccin_window_status_style "rounded"
          set -g @catppuccin_window_text " #W#{?window_zoomed_flag, Z,}"
          set -g @catppuccin_window_current_text " #W#{?window_zoomed_flag, Z,}"
          set -g status-right-length 100
          set -g status-right "#{E:@catppuccin_status_session}"
        '';
      }
      {
        plugin = resurrect;
        extraConfig = ''
          set -g @resurrect-capture-pane-contents 'on'
        '';
      }
      {
        plugin = continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
          set -g @continuum-save-interval '15'
        '';
      }
      {
        plugin = mkTmuxPlugin {
          pluginName = "tmux-assistant-resurrect";
          rtpFilePath = "tmux-assistant-resurrect.tmux";
          version = "unstable-2026-03-04";
          src = pkgs.fetchFromGitHub {
            owner = "timvw";
            repo = "tmux-assistant-resurrect";
            rev = "9e9792670211818b4ee0d9257e005f7290e95f91";
            sha256 = "0ny2q1g5r2ss1jxyqspdz0lliyvxvl33rs5s8k63l0k6112lf8bb";
          };
        };
      }
    ];
    terminal = "tmux-256color";

    extraConfig = ''
      set -s set-clipboard on
      set -g default-command zsh

      # Continuum's auto-restore races with plugin load order: it backgrounds
      # restore from its run-shell, before assistant-resurrect sets the
      # post-restore hooks. Disable it and trigger from here instead, after
      # all plugins and extraConfig have loaded.
      set -g @continuum-restore 'off'
      run-shell 'start=$(tmux display-message -p -F "#{start_time}"); now=$(date +%s); if [ $((now - start)) -lt 10 ] && [ -f ~/.tmux/resurrect/last ]; then sleep 1; "$(tmux show-option -gqv @resurrect-restore-script-path)"; fi &'

      # No delay after Escape (essential for vi copy mode)
      set -s escape-time 0
      set -g display-time 3000

      # Keep explicit window names set by scripts
      set -g allow-rename off
      set -g automatic-rename off

      # Status bar: session name on the right, window list on the left
      # Vi mode for copy, emacs for command prompt (prefix+:) where vi is lacking
      set -g status-keys emacs

      bind r source-file ~/.config/tmux/tmux.conf \; display "Config reloaded"

      # Vim-style pane navigation (repeatable, re-zooms if zoomed)
      bind -r h if -F "#{window_zoomed_flag}" "select-pane -L ; resize-pane -Z" "select-pane -L"
      bind -r j if -F "#{window_zoomed_flag}" "select-pane -D ; resize-pane -Z" "select-pane -D"
      bind -r k if -F "#{window_zoomed_flag}" "select-pane -U ; resize-pane -Z" "select-pane -U"
      bind -r l if -F "#{window_zoomed_flag}" "select-pane -R ; resize-pane -Z" "select-pane -R"

      # Vim-style pane resizing (repeatable, 5 cells per step)
      bind -r H resize-pane -L 5
      bind -r J resize-pane -D 5
      bind -r K resize-pane -U 5
      bind -r L resize-pane -R 5

      # Vi copy mode: v for visual selection, C-v for block selection
      bind -T copy-mode-vi v send -X begin-selection
      bind -T copy-mode-vi C-v send -X rectangle-toggle

      # Toggle last session
      bind Tab switch-client -l

      # Fuzzy session switcher (replaces built-in tree picker)
      bind s display-popup -E "tmux list-sessions -F '#S' | fzf --reverse | xargs tmux switch-client -t"

      # Create new session from project directory
      bind S display-popup -E "\
        fd -t d --max-depth 5 --exclude '.*' --exclude node_modules . ~ | fzf --reverse | while read dir; do \
          name=\$(basename \"\$dir\" | tr . _); \
          tmux new-session -d -s \"\$name\" -c \"\$dir\" 2>/dev/null; \
          tmux switch-client -t \"\$name\"; \
        done"
    '';
  };

  programs.ghostty = {
    enable = true;
    package = null;
    enableZshIntegration = true;
    settings = {
      theme = "Catppuccin Mocha";
      desktop-notifications = true;
      command = "zsh -l -c 'tmux new-session -As main'";
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

    sessionVariables =
      let
        paths = [
          "$BEALL_ROOT/bin"
        ];
        path = lib.concatStringsSep ":" paths;
      in
      {
        LANG = "en_US.UTF-8";

        LESS = "--no-init --quit-if-one-screen -R";

        PATH = "${path}:$PATH";

        BEALL_ROOT = "$HOME/Tech/Bespoke/beall";

        # Disable annoying docker scan warning message before each build command
        DOCKER_SCAN_SUGGEST = "false";
      };

    envExtra = ''
      # See https://discourse.nixos.org/t/why-can-i-not-execute-a-new-version-of-nix-with-nix-shell/31032
      [[ ! $(command -v nix) && -e "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]] && source "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
    '';

    initContent = ''
      eval "$(/opt/homebrew/bin/brew shellenv)"
      eval "$(zoxide init zsh)"
      source "$BEALL_ROOT/completion.zsh"
    '';

    oh-my-zsh = {
      enable = true;
      custom = "$HOME/.oh-my-zsh-custom";
      theme = "af-magic";
      plugins = [ "aliases" "aws" "beall-compose" "docker" "docker-compose" "git" "gcloud" "mise" "tmux" ];
    };
  };
}

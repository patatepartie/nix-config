{ lib, pkgs, ... }:
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
    # # parentheses. Maybe you want to install Nerd Fonts with a limited number of
    # # fonts?
    # (pkgs.nerdfonts.override { fonts = [ "FantasqueSansMono" ]; })

    # # You can also create simple shell scripts directly inside your
    # # configuration. For example, this adds a command 'my-hello' to your
    # # environment:
    # (pkgs.writeShellScriptBin "my-hello" ''
    #   echo "Hello, ${config.home.username}!"
    # '')

    pkgs.circleci-cli
    pkgs.curl
    pkgs.fzf
    pkgs.inetutils
    pkgs.jq
    pkgs.google-cloud-sdk
    pkgs.lastpass-cli
    pkgs.nil
    pkgs.nixpkgs-fmt
    pkgs.ngrok
    pkgs.nmap
    pkgs.pipx
    pkgs.reattach-to-user-namespace
    pkgs.ssm-session-manager-plugin
    pkgs.ruby_3_3

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
    ".tmux".source = dotfiles/tmux;
    ".oh-my-zsh-custom".source = dotfiles/oh-my-zsh;
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

  programs.git = {
    enable = true;

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
      };
      credential = {
        helper = "osxkeychain";
      };
      diff = {
        algorithm = "histogram";
        colorMoved = true;
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
    enable = true;
    clock24 = true;
    baseIndex = 1;
    historyLimit = 10000;
    mouse = true;

    extraConfig = ''
      set-option -g default-command "reattach-to-user-namespace -l zsh"
      bind-key -T copy-mode-vi 'y' send -X copy-pipe-and-cancel 'reattach-to-user-namespace pbcopy'
      bind-key -T copy-mode-vi Enter send -X copy-pipe-and-cancel 'reattach-to-user-namespace pbcopy'
    '';
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

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
      source "$BEALL_ROOT/completion.zsh"
    '';

    oh-my-zsh = {
      enable = true;
      custom = "$HOME/.oh-my-zsh-custom";
      theme = "af-magic";
      plugins = [ "aliases" "aws" "beall-compose" "docker" "docker-compose" "git" "gcloud" "tmux" ];
    };
  };
}

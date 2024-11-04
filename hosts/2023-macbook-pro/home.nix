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
    pkgs.obsidian
    pkgs.ruby_3_3

    (pkgs.writeShellScriptBin "capture.zsh"
      (pkgs.fetchFromGitHub {
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
    userName = "Cyril Ledru";
    userEmail = "cyril@lev-art.com";

    lfs.enable = true;

    ignores = [
      ".idea"
      "*.iml"
      ".DS_Store"
      "venv"
      ".vscode"
    ];

    extraConfig = {
      color = {
        ui = true;
      };
      core = {
        editor = "vim";
        ignorecase = false;
      };
      credential = {
        helper = "osxkeychain";
      };
      diff = {
        wsErrorHighlight = "all";
      };
      fetch = {
        prune = true;
      };
      init = {
        defaultBranch = "master";
      };
      merge = {
        tool = "p4merge";
        conflictStyle = "diff3";
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
      };
    };
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

    initExtra = ''
      eval "$(/opt/homebrew/bin/brew shellenv)"
      source "$BEALL_ROOT/completion.zsh"
    '';

    oh-my-zsh = {
      enable = true;
      custom = "$HOME/.oh-my-zsh-custom";
      theme = "af-magic";
      plugins = [ "aliases" "aws" "beall-compose" "brew" "direnv" "docker" "docker-compose" "git" "gcloud" "sublime" "tmux" ];
    };
  };

  programs.vscode = {
    enable = true;
    enableUpdateCheck = false;
    mutableExtensionsDir = false;
    # To upgrade an extension, find the new version on the marketplace, replace it, then use lib.sha256 for the sha256 attribute.
    # Apply the change, then copy the "got" value from the error message and paste it in the sha256 attribute.
    extensions = pkgs.vscode-utils.extensionsFromVscodeMarketplace [
      {
        name = "copilot";
        publisher = "github";
        version = "1.222.0";
        sha256 = "sha256-VnZkBXm4lU+QMAVF4D5jpwOiRwBf80EWeKZoxN2gKfs=";
      }
      {
        name = "copilot-chat";
        publisher = "github";
        version = "0.19.2024073102";
        sha256 = "sha256-ekRBmJiAav1gITWlqBOuWtZMt1YZeseF+3fw326db/s=";
      }
      {
        name = "nix-ide";
        publisher = "jnoortheen";
        version = "0.3.3";
        sha256 = "sha256-/vBbErwwecQhsqQwnw8ijooof8DPWt85symLQQtBC+Y=";
      }
      {
        name = "prettier-vscode";
        publisher = "esbenp";
        version = "10.4.0";
        sha256 = "sha256-8+90cZpqyH+wBgPFaX5GaU6E02yBWUoB+T9C2z2Ix8c=";
      }
      {
        name = "python";
        publisher = "ms-python";
        version = "2024.13.2024081301";
        sha256 = "sha256-XHx7DOw27k945+KNjfbod0D6AqUnfLHDTXKCz0e38ho=";
      }
      {
        name = "rainbow-csv";
        publisher = "mechatroner";
        version = "3.12.0";
        sha256 = "sha256-pnHaszLa4a4ptAubDUY+FQX3F6sQQUQ/sHAxyZsbhcQ=";
      }
      {
        name = "remote-containers";
        publisher = "ms-vscode-remote";
        version = "0.381.0";
        sha256 = "sha256-qGDLpEHQBB1x++KD+xrcJTs8oGmZJXjsUojfG3TwczI=";
      }
      {
        name = "ruby-lsp";
        publisher = "shopify";
        version = "0.7.15";
        sha256 = "sha256-8Ycoq8M9DT7aTOH4qb/oknLl3KpINDdbrQxf44mV+KQ";
      }
      {
        name = "terraform";
        publisher = "hashicorp";
        version = "2.33.2024080812";
        sha256 = "sha256-4tr77tXoE/HUM3YU0Kz1760tfBOlXDygpdlPaa+PrSg=";
      }
      {
        name = "vscode-yaml";
        publisher = "redhat";
        version = "1.15.0";
        sha256 = "sha256-NhlLNYJryKKRv+qPWOj96pT2wfkiQeqEip27rzl2C0M=";
      }
    ];
    userSettings = {
      "aws.samcli.lambdaTimeout" = 1234;
      "files.autoSave" = "afterDelay";
      "files.trimTrailingWhitespace" = true;
      "files.insertFinalNewline" = true;
      "files.trimFinalNewlines" = true;
      "editor.tabSize" = 2;
      "editor.minimap.enabled" = false;
      "editor.inlineSuggest.enabled" = true;
      "explorer.autoReveal" = false;
      "explorer.confirmDelete" = false;
      "extensions.autoUpdate" = false;
      "extensions.ignoreRecommendations" = true;
      "github.copilot.enable" = {
        "*" = true;
        "plaintext" = false;
        "markdown" = false;
        "scminput" = false;
        "yaml" = false;
      };
      "nix.enableLanguageServer" = true;
      "nix.serverPath" = "nil";
      "nix.serverSettings" = {
        "nil" = {
          "formatting" = {
            "command" = [
              "nixpkgs-fmt"
            ];
          };
        };
      };
      "[css]" = {
        "editor.defaultFormatter" = "esbenp.prettier-vscode";
      };
      "[html]" = {
        "editor.defaultFormatter" = "esbenp.prettier-vscode";
      };
      "[javascript]" = {
        "editor.defaultFormatter" = "esbenp.prettier-vscode";
      };
      "[json]" = {
        "editor.defaultFormatter" = "esbenp.prettier-vscode";
      };
      "[jsonc]" = {
        "editor.defaultFormatter" = "esbenp.prettier-vscode";
      };
      "[nix]" = {
        "editor.defaultFormatter" = "jnoortheen.nix-ide";
      };
      "[python]" = {
        "editor.insertSpaces" = true;
        "editor.tabSize" = 4;
      };
      "editor.stickyScroll.enabled" = false;
      "workbench.colorTheme" = "Default Dark+";
    };
  };
}

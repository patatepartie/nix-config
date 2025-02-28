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
    mutableExtensionsDir = false;
    profiles.default = {
      enableUpdateCheck = false;
      # To upgrade an extension, find the new version on the marketplace, replace it below, then use lib.fakeSha256 as the value for the sha256 attribute.
      # Apply the change, then copy the "got" value from the error message and paste it in the sha256 attribute.
      extensions = pkgs.vscode-utils.extensionsFromVscodeMarketplace [
        {
          name = "copilot";
          publisher = "github";
          version = "1.276.1400";
          sha256 = "sha256-yi2uqrSmFfMl8hz7e17PE483binEWJAunpfaP+8y1Uk=";
        }
        # To find the correct version, check the vscode version in the About dialog, then use the following command:
        # nix run nixpkgs#vsce -- show github.copilot-chat --json | less
        # and look for the version that matches the vscode version.
        {
          name = "copilot-chat";
          publisher = "github";
          version = "0.24.2025021302";
          sha256 = "sha256-+lb+fo5PvEvWrQlyMi72SJ8bVwd8zTU2tDK+jJJSkPA=";
        }
        {
          name = "nix-ide";
          publisher = "jnoortheen";
          version = "0.4.12";
          sha256 = "sha256-3pXypgAwg/iEBUqPeNsyoX2oYqlKMVdemEhmhy1PuGU=";
        }
        {
          name = "prettier-vscode";
          publisher = "esbenp";
          version = "11.0.0";
          sha256 = "sha256-pNjkJhof19cuK0PsXJ/Q/Zb2H7eoIkfXJMLZJ4lDn7k=";
        }
        {
          name = "python";
          publisher = "ms-python";
          version = "2025.1.2025022501";
          sha256 = "sha256-hPVT86Uvok4BAKbbB6FhjWxQoEY/TWVKCliEn/+QNWY=";
        }
        {
          name = "rainbow-csv";
          publisher = "mechatroner";
          version = "3.17.0";
          sha256 = "sha256-qny0LU0+Q38H0BMC4Njk173KDuLjebxZN3Bg8vSDVLA=";
        }
        {
          name = "remote-containers";
          publisher = "ms-vscode-remote";
          version = "0.400.0";
          sha256 = "sha256-UXgyFzzM19Elpdtza6zwXxSGg69ddBwVIe+m0anc9AE=";
        }
        {
          name = "ruby-lsp";
          publisher = "shopify";
          version = "0.9.7";
          sha256 = "sha256-7vLT5vvqqwT0Tlt/iHXW0ktp2It7l+lxUWNJEljIp4c=";
        }
        {
          name = "terraform";
          publisher = "hashicorp";
          version = "2.34.2025012311";
          sha256 = "sha256-SmADVhgysDDvmI2/FZHoNWfgSrcxQfJTJj4ZgxOxjhc=";
        }
        {
          name = "vscode-yaml";
          publisher = "redhat";
          version = "1.16.0";
          sha256 = "sha256-3cuonI98gVFE/GwPA7QCA1LfSC8oXqgtV4i6iOngwhk=";
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
  };
}

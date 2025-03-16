{ lib, pkgs, ... }: {
  home.username = "patate";
  home.homeDirectory = "/home/patate";

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "23.05"; # Please read the comment before changing.

  programs.git = {
    enable = true;
    userName = "Cyril Ledru";
    userEmail = "cyril.ledru@gmail.com";

    ignores = [
      "*.swp"
    ];

    extraConfig = {
      color = {
        ui = true;
      };
      core = {
        editor = "vim";
        ignorecase = false;
      };
      diff = {
        wsErrorHighlight = "all";
      };
      fetch = {
        prune = true;
      };
      init = {
        defaultBranch = "main";
      };
      pull = {
        ff = "only";
      };
      push = {
        default = "simple";
      };
    };
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    history.share = false;

    oh-my-zsh = {
      enable = true;
      theme = "af-magic";
      plugins = [ "aliases" "git" "tmux" ];
    };
  };

  programs.tmux = {
    enable = true;
    clock24 = true;
    baseIndex = 1;
    historyLimit = 10000;
    mouse = true;
  };

  dconf.settings = with lib.hm.gvariant; {
    "org/gnome/desktop/input-sources" = {
      sources = [ (mkTuple [ "xkb" "jp" ]) (mkTuple [ "xkb" "us" ]) ];
      xkb-options = [ "terminate:ctrl_alt_bksp" ];
    };

    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };

    "org/gnome/desktop/peripherals/keyboard" = {
      numlock-state = true;
    };

    "org/gnome/desktop/remote-desktop/rdp" = {
      enable = true;
      tls-cert = "/home/patate/.local/share/gnome-remote-desktop/rdp-tls.crt";
      tls-key = "/home/patate/.local/share/gnome-remote-desktop/rdp-tls.key";
      view-only = false;
    };

    "org/gnome/desktop/session" = {
      idle-delay = mkUint32 0;
    };

    "org/gnome/settings-daemon/plugins/power" = {
      power-button-action = "interactive";
      sleep-inactive-ac-type = "nothing";
    };

    "system/locale" = {
      region = "en_US.UTF-8";
    };
  };

  home.packages = with pkgs; [
    retroarchFull
    transmission_4-gtk
    vlc
    google-chrome
  ];
}

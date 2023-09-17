{ config, lib, pkgs, ... }: {
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
    enableAutosuggestions = true;
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
}

{ config, ... }: {
  # Install homebrew and prerequisites if not already present
  system.activationScripts.preUserActivation.text = ''
    if ! xcode-select --version 2>/dev/null; then
      $DRY_RUN_CMD xcode-select --install
    fi
  '';

  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup = "zap";
      upgrade = true;
    };

    taps = builtins.attrNames config.nix-homebrew.taps;

    brews = [
    ];

    casks = [
      "google-chrome"
      "google-drive"
      "firefox"
      "microsoft-remote-desktop"
      "obsidian"
      "p4v"
      "slack"
      "spotify"
      "visual-studio-code@insiders"
      "vlc"
    ];
  };
}

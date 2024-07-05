{ ... }: {
  # Install homebrew and prerequisites if not already present
  system.activationScripts.preUserActivation.text = ''
    if ! xcode-select --version 2>/dev/null; then
      $DRY_RUN_CMD xcode-select --install
    fi
  '';

  homebrew = {
    enable = true;
    global.autoUpdate = true;

    brews = [
      "docker-credential-helper-ecr"
    ];

    casks = [
      "anki"
      "balenaetcher"
      "deepl"
      "firefox"
      "google-chrome"
      "karabiner-elements"
      "microsoft-remote-desktop"
      "nordvpn"
      "p4v"
      "postman"
      "slack"
      "spotify"
      "steam"
      "transmission"
      "vlc"
      "zoom"
    ];
  };
}

{ ... }: {
  # Install homebrew and prerequisites if not already present
  system.activationScripts.preUserActivation.text = ''
    if ! xcode-select --version 2>/dev/null; then
      $DRY_RUN_CMD xcode-select --install
    fi
    if ! /usr/local/bin/brew --version 2>/dev/null; then
      $DRY_RUN_CMD /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
  '';

  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup = "zap";
      upgrade = true;
    };

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

{ ... }: {
  # Install homebrew and prerequisites if not already present
  system.activationScripts.preUserActivation.text = ''
    if ! xcode-select --version 2>/dev/null; then
      $DRY_RUN_CMD xcode-select --install
    fi
  '';

  homebrew = {
    enable = true;
    global.autoUpdate = false;

    onActivation = {
      autoUpdate = true;
      upgrade = true;
    };

    brews = [
      "awscli"
      "docker-credential-helper-ecr"
      "mise"
    ];

    casks = [
      "anki"
      "android-platform-tools"
      "balenaetcher"
      "deepl"
      "firefox"
      "ghostty"
      "google-chrome"
      "google-drive"
      "gnucash"
      "joplin"
      "karabiner-elements"
      "microsoft-remote-desktop"
      "nordvpn"
      "p4v"
      "postman"
      "skype"
      "slack"
      "spotify"
      "steam"
      "transmission"
      "vlc"
      "zoom"
    ];
  };
}

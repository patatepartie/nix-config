{ pkgs, ... }: {
  # Make sure the nix daemon always runs
  services.nix-daemon.enable = true;

  # Necessary for using flakes on this system.
  nix.settings.experimental-features = "nix-command flakes";

  # Create /etc/zshrc that loads the nix-darwin environment.
  programs.zsh.enable = true;

  # Set Git commit hash for darwin-version.
  # system.configurationRevision = self.rev or self.dirtyRev or null;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 4;

  # The platform the configuration will be used on.
  # nixpkgs.hostPlatform = "x86_64-darwin";

  nixpkgs.config.allowUnfree = true;

  # That's a bit redundant but necessary because of: https://github.com/nix-community/home-manager/issues/4026
  users.users.cyrilledru = {
    name = "cyrilledru";
    home = "/Users/cyrilledru";
  };

  # Requires Homebrew to be installed
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
      cleanup = "none"; # Do not uninstall non-listed packages
      upgrade = true;
    };

    brews = [
    ];

    casks = [
      "anki"
      "balenaetcher"
      "firefox"
      "p4v"
      "postman"
      "spotify"
      "steam"
      "transmission"
      "vlc"
    ];
  };
}

{ pkgs, ... }:
let
  username = "cyrilledru";
in {
  # Make sure the nix daemon always runs
  services.nix-daemon.enable = true;

  # Necessary for using flakes on this system.
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  nixpkgs.config.allowUnfree = true;

  # Make sure nix is the latest version in nixpkgs
  nix.package = pkgs.nix;

  # nix-index is a tool to quickly locate the package providing a certain file in nixpkgs.
  # Looks useful.
  programs.nix-index.enable = true;

  # do garbage collection weekly to keep disk usage low
  nix.gc = {
    automatic = true;
    options = "--delete-older-than 1w";
  };

  # Nix automatically detects files in the store that have identical contents,
  # and replaces them with hard links to a single copy.
  nix.settings.auto-optimise-store = true;

  nix.settings.trusted-users = [ username ];

  # Create /etc/zshrc that loads the nix-darwin environment.
  programs.zsh.enable = true;
  environment = {
    loginShell = pkgs.zsh;
  };

  system = {
    # Used for backwards compatibility, please read the changelog before changing.
    # $ darwin-rebuild changelog
    stateVersion = 4;

    activationScripts.postUserActivation.text = ''
      # Following line should allow us to avoid a logout/login cycle
      /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
    '';

    keyboard = {
      enableKeyMapping = true;
      remapCapsLockToControl = true;
    };

    defaults = {
      NSGlobalDomain = {
        AppleShowAllExtensions = true;
        AppleTemperatureUnit = "Celsius";
        InitialKeyRepeat = 30;
        KeyRepeat = 5;

        "com.apple.swipescrolldirection" = false;

        "com.apple.springing.enabled" = true;
        "com.apple.springing.delay" = 0.5;
      };

      ".GlobalPreferences" = {
        "com.apple.mouse.scaling" = "1.5";
      };

      ActivityMonitor = {
        IconType = 6;
        OpenMainWindow = true;
        ShowCategory = 100;
      };

      dock = {
        autohide = true;
        largesize = 128;
      };

      finder = {
        AppleShowAllExtensions = true;
        FXDefaultSearchScope = "SCcf";
        FXEnableExtensionChangeWarning = false;
        FXPreferredViewStyle = "clmv";
        ShowStatusBar = true;
      };

      trackpad = {
        Clicking = false;
        Dragging = false;
        FirstClickThreshold = 1;
        SecondClickThreshold = 1;
        TrackpadRightClick = false;
        TrackpadThreeFingerDrag = false;
      };

      magicmouse = {
        MouseButtonMode = "TwoButton";
      };
    };
  };

  # Set Git commit hash for darwin-version.
  # system.configurationRevision = self.rev or self.dirtyRev or null;

  security.pam.enableSudoTouchIdAuth = true;

  # The platform the configuration will be used on.
  # nixpkgs.hostPlatform = "x86_64-darwin";

  # That's a bit redundant but necessary because of: https://github.com/nix-community/home-manager/issues/4026
  users.users."${username}" = {
    name = username;
    home = "/Users/${username}";
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

{ ... }: {
  system = {
    # Used for backwards compatibility, please read the changelog before changing.
    # $ darwin-rebuild changelog
    stateVersion = 5;

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
        ApplePressAndHoldEnabled = true;
        AppleShowAllExtensions = true;
        AppleTemperatureUnit = "Celsius";
        InitialKeyRepeat = 30;
        KeyRepeat = 5;

        "com.apple.swipescrolldirection" = false;

        "com.apple.springing.enabled" = true;
        "com.apple.springing.delay" = 0.5;

        "com.apple.trackpad.scaling" = 2.0;
      };

      ".GlobalPreferences" = {
        "com.apple.mouse.scaling" = 1.5;
      };

      CustomUserPreferences = {
        "com.apple.AppleMultitouchTrackpad" = {
          TrackpadCornerSecondaryClick = 2;
        };
      };

      ActivityMonitor = {
        IconType = 6;
        OpenMainWindow = true;
        ShowCategory = 100;
      };

      dock = {
        autohide = false;
        orientation = "left";
        tilesize = 48;
        largesize = 128;

        show-recents = false;
        mru-spaces = false;

        persistent-apps = [
          {
            app = "/System/Applications/Launchpad.app";
          }
          {
            app = "/Applications/Google Chrome.app";
          }
          {
            app = "/Applications/Visual Studio Code.app";
          }
          {
            app = "/Applications/Obsidian.app";
          }
          {
            app = "/Applications/Slack.app";
          }
          {
            app = "/System/Applications/Utilities/Terminal.app";
          }
          {
            app = "/Applications/Spotify.app";
          }
          {
            app = "/System/Applications/Utilities/Activity Monitor.app";
          }
          {
            app = "/System/Applications/System Settings.app";
          }
        ];

        persistent-others = [
          "/Users/cyrilledru/Tech"
          "/Users/cyrilledru/Downloads"
        ];
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

  # Add ability to used TouchID for sudo authentication
  security.pam.services.sudo_local.touchIdAuth = true;

  # Create /etc/zshrc that loads the nix-darwin environment.
  programs.zsh.enable = true;
}

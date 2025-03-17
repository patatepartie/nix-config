{ pkgs, ... }: {
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
      nonUS.remapTilde = true;
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
      };

      ".GlobalPreferences" = {
        "com.apple.mouse.scaling" = 1.5;
      };

      ActivityMonitor = {
        IconType = 6;
        OpenMainWindow = true;
        ShowCategory = 100;
      };

      dock = {
        autohide = false;
        largesize = 128;
        orientation = "left";
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

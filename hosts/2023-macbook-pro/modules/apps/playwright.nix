{ username, ... }: {
  homebrew.brews = [ "playwright-cli" ];

  # playwright-cli sessions must pass --browser=chromium, or they drive the real
  # /Applications/Google Chrome.app and block Chrome from starting. That flag
  # fails hard unless this build is present.
  home-manager.users.${username} = { lib, ... }: {
    home.activation.installPlaywrightBrowsers = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ -x /opt/homebrew/bin/playwright-cli ]; then
        run /opt/homebrew/bin/playwright-cli install-browser chromium
      fi
    '';
  };
}

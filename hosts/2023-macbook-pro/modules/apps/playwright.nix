{ username, ... }: {
  homebrew.brews = [ "playwright-cli" ];

  # Without a matching browser revision, playwright-cli drives the real
  # /Applications/Google Chrome.app and blocks Chrome from starting.
  home-manager.users.${username} = { lib, ... }: {
    home.activation.installPlaywrightBrowsers = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ -x /opt/homebrew/bin/playwright-cli ]; then
        run /opt/homebrew/bin/playwright-cli install-browser chromium
      fi
    '';
  };
}

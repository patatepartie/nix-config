{ username, ... }:
{
  homebrew.brews = [ "playwright-cli" ];

  home-manager.users.${username} = { lib, ... }: {
    # playwright-cli defaults to browser-type "chrome", which drives the real
    # /Applications/Google Chrome.app and blocks Chrome from starting. This is
    # the lowest-precedence config it reads, so a project or a flag can still
    # override it.
    home.file.".playwright/cli.config.json".text = builtins.toJSON {
      browser.browserName = "chromium";
    };

    home.activation.installPlaywrightBrowsers = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ -x /opt/homebrew/bin/playwright-cli ]; then
        run /opt/homebrew/bin/playwright-cli install-browser chromium
      fi
    '';
  };
}

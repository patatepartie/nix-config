{ pkgs, username, ... }:
let
  # Homebrew's node fails to load libsimdutf on Sonoma: merve has no Tier 3
  # bottle for the newer simdutf. Drop this and call the brew binary directly
  # once the machine is on Tahoe.
  playwrightCli = "${pkgs.nodejs}/bin/node /opt/homebrew/bin/playwright-cli";
in
{
  homebrew.brews = [ "playwright-cli" ];

  # playwright-cli sessions must pass --browser=chromium, or they drive the real
  # /Applications/Google Chrome.app and block Chrome from starting. That flag
  # fails hard unless this build is present.
  home-manager.users.${username} = { lib, ... }: {
    programs.zsh.shellAliases.playwright-cli = playwrightCli;

    home.activation.installPlaywrightBrowsers = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ -x /opt/homebrew/bin/playwright-cli ]; then
        run ${playwrightCli} install-browser chromium
      fi
    '';
  };
}

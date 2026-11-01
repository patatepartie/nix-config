{ config, ... }: {
  # Install homebrew and prerequisites if not already present
  system.activationScripts.postActivation.text = ''
    if ! xcode-select --version 2>/dev/null; then
      $DRY_RUN_CMD xcode-select --install
    fi
  '';

  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;
      cleanup = "uninstall";
      upgrade = true;
    };

    taps = builtins.attrNames config.nix-homebrew.taps;
  };

  # /etc/zshenv resets PATH to this in every zsh, so non-interactive shells
  # never see the `brew shellenv` in home.nix. See ADR 0002.
  environment.systemPath = [ "/opt/homebrew/bin" ];
}

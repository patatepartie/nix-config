{ config, ... }: {
  # Install homebrew and prerequisites if not already present
  system.activationScripts.ensureXcodeIsInstalled.text = ''
    if ! xcode-select --version 2>/dev/null; then
      $DRY_RUN_CMD xcode-select --install
    fi
  '';

  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup = "zap";
      upgrade = true;
    };

    taps = builtins.attrNames config.nix-homebrew.taps;

    brews = [
      "awscli"
      "docker-credential-helper-ecr"
      "libyaml"
      "mise"
    ];

    casks = [
    ];
  };
}

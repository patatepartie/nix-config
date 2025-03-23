{ config, ... }: {
  # Install homebrew and prerequisites if not already present
  system.activationScripts.preUserActivation.text = ''
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
    ];

    casks = [
      "google-chrome"
      "google-drive"
      "firefox"
      "microsoft-remote-desktop"
      "obsidian"
      "p4v"
      "slack"
      "spotify"
      "visual-studio-code"
      "vlc"
    ];
  };

  system.activationScripts.postUserActivation.text = ''
    install_command="/usr/local/bin/code"
    for package in esbenp.prettier-vscode github.copilot github.copilot-chat hashicorp.terraform jnoortheen.nix-ide mechatroner.rainbow-csv ms-python.python ms-vscode-remote.remote-containers redhat.vscode-yaml shopify.ruby-lsp; do
      install_command="$install_command  --install-extension $package"
    done
    eval "$install_command"
  '';
}

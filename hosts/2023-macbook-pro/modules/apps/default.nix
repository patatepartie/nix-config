{ ... }: {
  imports = [
    ./homebrew.nix
    ./brews.nix
    ./casks.nix
    ./mas.nix
    ./playwright.nix
    ./vscode.nix
  ];
}

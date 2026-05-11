{ ... }:
let greedy = name: { inherit name; greedy = true; };
in {
  homebrew.casks = [
    (greedy "gnucash")
    (greedy "google-drive")
    (greedy "obsidian")
    (greedy "spotify")
    (greedy "vlc")
    (greedy "windows-app")
  ] ++ [
    "claude-code"
    "firefox"
    "ghostty"
    "google-chrome"
    "slack"
  ];
}

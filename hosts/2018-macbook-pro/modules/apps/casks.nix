{ ... }:
let greedy = name: { inherit name; greedy = true; };
in {
  homebrew.casks = [
    (greedy "gnucash")
    (greedy "google-drive")
    (greedy "obsidian")
    (greedy "p4v")
    (greedy "spotify")
    (greedy "vlc")
    (greedy "windows-app")
  ] ++ [
    "firefox"
    "ghostty"
    "google-chrome"
    "slack"
  ];
}

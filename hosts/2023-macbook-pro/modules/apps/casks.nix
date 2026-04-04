{ ... }:
let greedy = name: { inherit name; greedy = true; };
in {
  homebrew.casks = [
    (greedy "anki")
    (greedy "balenaetcher")
    (greedy "claude-code@latest")
    (greedy "deepl")
    (greedy "ghostty")
    (greedy "google-drive")
    (greedy "karabiner-elements")
    (greedy "nordvpn")
    (greedy "obsidian")
    (greedy "p4v")
    (greedy "spotify")
    (greedy "vlc")
    (greedy "windows-app")
  ] ++ [
    "claude"
    "firefox"
    "google-chrome"
    "slack"
  ];
}

{ ... }: {
  homebrew.casks = [
    { name = "anki"; greedy = true; }
    { name = "balenaetcher"; greedy = true; }
    { name = "claude-code"; greedy = true; }
    { name = "deepl"; greedy = true; }
    { name = "ghostty"; greedy = true; }
    { name = "google-drive"; greedy = true; }
    { name = "karabiner-elements"; greedy = true; }
    { name = "nordvpn"; greedy = true; }
    { name = "obsidian"; greedy = true; }
    { name = "p4v"; greedy = true; }
    { name = "spotify"; greedy = true; }
    { name = "vlc"; greedy = true; }
    { name = "windows-app"; greedy = true; }
  ] ++ [
    "claude"
    "firefox"
    "google-chrome"
    "slack"
  ];
}

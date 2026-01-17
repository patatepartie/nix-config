{ ... }: {
  homebrew.casks = [
    { name = "gnucash"; greedy = true; }
    { name = "google-drive"; greedy = true; }
    { name = "obsidian"; greedy = true; }
    { name = "p4v"; greedy = true; }
    { name = "spotify"; greedy = true; }
    { name = "vlc"; greedy = true; }
    { name = "windows-app"; greedy = true; }
  ]  ++ [
    "docker-desktop"
    "firefox"
    "google-chrome"
    "slack"
  ];
}

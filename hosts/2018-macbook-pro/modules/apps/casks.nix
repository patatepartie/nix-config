{ ... }:
let greedy = name: { inherit name; greedy = true; };
in {
  homebrew.casks = [
    (greedy "gnucash")
    (greedy "google-drive")
    (greedy "vlc")
  ] ++ [
    "claude-code"
    "coteditor"
    "ghostty"
    "google-chrome"
  ];
}

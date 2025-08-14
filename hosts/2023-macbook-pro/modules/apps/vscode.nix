{ ... }: {
  homebrew.casks = [
    { name = "visual-studio-code"; greedy = true; }
  ];

  system.activationScripts.installVSCodeExtensions.text = ''
    install_command="/opt/homebrew/bin/code"
    for package in esbenp.prettier-vscode github.copilot github.copilot-chat hashicorp.terraform jnoortheen.nix-ide \
      mechatroner.rainbow-csv ms-python.python ms-vscode-remote.remote-containers redhat.vscode-yaml shopify.ruby-lsp \
      tamasfe.even-better-toml hverlin.mise-vscode; do
      install_command="$install_command  --install-extension $package"
    done
    eval "$install_command"
  '';
}

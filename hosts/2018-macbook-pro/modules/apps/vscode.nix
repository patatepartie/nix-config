{ ... }: {
  homebrew.casks = ["visual-studio-code"];

  system.activationScripts.installVSCodeExtensions.text = ''
    install_command="/usr/local/bin/code"
    for package in esbenp.prettier-vscode github.copilot github.copilot-chat hashicorp.terraform jnoortheen.nix-ide \
      mechatroner.rainbow-csv ms-python.python ms-vscode-remote.remote-containers redhat.vscode-yaml shopify.ruby-lsp; do
      install_command="$install_command  --install-extension $package"
    done
    eval "$install_command"
  '';
}

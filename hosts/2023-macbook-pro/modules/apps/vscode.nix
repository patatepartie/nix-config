{ username, ... }: {
  homebrew.casks = [
    { name = "visual-studio-code"; greedy = true; }
  ];

  home-manager.users.${username} = { lib, ... }: {
    home.activation.installVSCodeExtensions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ -x /opt/homebrew/bin/code ]; then
        for package in esbenp.prettier-vscode hashicorp.terraform jnoortheen.nix-ide \
          mechatroner.rainbow-csv ms-python.python ms-vscode-remote.remote-containers redhat.vscode-yaml shopify.ruby-lsp \
          tamasfe.even-better-toml hverlin.mise-vscode; do
          run /opt/homebrew/bin/code --install-extension "$package"
        done
      fi
    '';
  };
}

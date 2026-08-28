{ username, ... }: {
  homebrew.casks = [
    { name = "visual-studio-code"; greedy = true; }
  ];

  home-manager.users.${username} = { lib, ... }: {
    home.activation.installVSCodeExtensions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ -x /usr/local/bin/code ]; then
        for package in esbenp.prettier-vscode hashicorp.terraform jnoortheen.nix-ide \
          mechatroner.rainbow-csv ms-python.python ms-vscode-remote.remote-containers redhat.vscode-yaml shopify.ruby-lsp; do
          run /usr/local/bin/code --install-extension "$package"
        done
      fi
    '';
  };
}

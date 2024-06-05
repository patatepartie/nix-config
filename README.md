Login to LP

https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent

```bash
# Passphrase auto-generated by LastPass and kept there in an SSH key entry
ssh-keygen -t ed25519 -C "WORK EMAIL"
eval "$(ssh-agent -s)"
touch ~/.ssh/config
open ~/.ssh/config
```

```
Host github.com
  AddKeysToAgent yes
  UseKeychain yes
  IdentityFile ~/.ssh/id_ed25519
```

```bash
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

Add key to github
https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account

```bash
pbcopy < ~/.ssh/id_ed25519.pub
```
Can also be used to fill the LP entry

Test connection
https://docs.github.com/en/authentication/connecting-to-github-with-ssh/testing-your-ssh-connection
```bash
ssh -T git@github.com
```

```bash
mkdir ~/Tech
cd ~/Tech
nix run nixpkgs#git -- clone git@github.com:patatepartie/nix-config.git
cd nix-config
```

First run:
```bash
nix run nix-darwin -- switch --flake .
```

Following runs, once nix tools are installed globally:
```bash
darwin-rebuild -- switch --flake .
```
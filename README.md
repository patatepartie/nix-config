### Installation

#### Install nix

Use the determinate installer: https://github.com/DeterminateSystems/nix-installer
Make sure you reply "no" to the first question, so that you install the NixOS installer and not the determinate one.

#### Generate a new SSH Key

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

Create an entry for the SSH key in LastPass.

#### Checkout the repository

```bash
mkdir ~/Tech
cd ~/Tech
nix run nixpkgs#git clone git@github.com:patatepartie/nix-config.git
cd nix-config
```

#### Initial

Ensure your machine has the correct hostname (the one used in flake.nix), otherwise change it using:
```bash
sudo scutil --set HostName <newi_hostname>
```

Now, execute the first run:
```bash
nix run nix-darwin -- switch --flake .
```

The following runs, once nix tools are installed globally, will be:
```bash
darwin-rebuild switch --flake .
```

### GnuCash

While the software works well when installed using HomeBrew (I didn't try with direct nix install),
I couldn't not figure out a declarative way to make the automatic retrieval of exchange rates work.

Using multiple currencies is explained [here](https://www.gnucash.org/docs/v5/C/gnucash-guide/chapter_currency.html)
but making the automatic retrieval is explained [here](https://www.gnucash.org/docs/v5/C/gnucash-manual/finance-quote.html).

The main command is to run `sudo /Applications/Gnucash.app/Contents/Resources/bin/gnc-fq-update`.
Unfortunately, this does not work fully.
The rest is explained [here](https://www.reddit.com/r/GnuCash/comments/12c250i/online_quotes_stopped_working/).

I'm not 100% sure what are the minimal steps to make it work, but those ended up working:
- Follow [those steps](https://www.reddit.com/r/GnuCash/comments/12c250i/comment/jh1y9ao/)
  - `sudo perl -MCPAN -e shell`
  - `install App::cpanminus`
  - `exit`
  - `sudo cpanm --uninstall Finance::Quote`
  - `sudo cpanm --uninstall JSON::Parse`
  - Quit Terminal and re-open with Rosetta enabled
  - `sudo /Applications/Gnucash.app/Contents/Resources/bin/gnc-fq-update`
- Now, following [this](https://www.reddit.com/r/GnuCash/comments/12c250i/comment/kuq2fgq/), run:
  - `sudo cpanm --force Finance::Quote`
- And back to the first link, test that it worked:
  - `/Applications/Gnucash.app/Contents/MacOS/gnucash-cli --quotes info`
  - It works if you get a list of APIs and not an error message
- Lastly, one step that was harder to find, following [this](https://wiki.gnucash.org/wiki/Online_Quotes#Source_Alphavantage.2C_US):
  - Get a Free API key on the Alpha Vantage [site](https://www.alphavantage.co/) (I already have one in LastPass, in `AlphaVantage API key`)
  - Set it in `GnuCash Preferences > Online Quotes > Alpha Vantage API Key`

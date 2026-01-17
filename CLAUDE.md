# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a Nix flake-based configuration for managing multiple machines:
- **Cyrils-MacBook-Pro** (2023): Apple Silicon macOS using nix-darwin
- **Cyrils-2018-MacBook-Pro**: Intel macOS using nix-darwin
- **home-server**: NixOS x86_64 Linux server

## Common Commands

### macOS (nix-darwin)

First-time setup:
```bash
nix run nix-darwin -- switch --flake .
```

Apply configuration changes:
```bash
sudo darwin-rebuild switch --flake .
```

### NixOS (home-server)

Apply configuration changes (run on the server):
```bash
nixos-rebuild switch  --sudo --flake .
```

### Updating

Update flake inputs:
```bash
nix flake update
```

## Architecture

### Flake Structure

`flake.nix` defines three system configurations using:
- `nix-darwin` for macOS systems
- `nixpkgs.lib.nixosSystem` for NixOS
- `home-manager` integrated into both via their respective modules
- `nix-homebrew` for declarative Homebrew management on macOS

### Host Configuration Pattern

Each host in `hosts/<hostname>/` follows this structure:
- `default.nix`: Entry point that composes modules
- `home.nix`: User-specific configuration via home-manager
- `modules/`: Host-specific system configuration
  - `nix-core.nix`: Nix daemon and package settings
  - `system.nix`: System preferences (keyboard, dock, finder on macOS)
  - `host-users.nix`: User accounts
  - `apps/`: Application installations (Homebrew casks, brews, Mac App Store apps)

### macOS App Management

Applications on macOS are managed through multiple channels in `modules/apps/`:
- `casks.nix`: GUI applications via Homebrew Cask
- `brews.nix`: CLI tools via Homebrew
- `mas.nix`: Mac App Store applications
- `vscode.nix`: VS Code extensions
- `homebrew.nix`: Base Homebrew configuration

### Home Manager

User environment configuration (dotfiles, shell config, git) is in `home.nix` for each host. The 2023 MacBook Pro's `home.nix` includes:
- Shell configuration (zsh with oh-my-zsh)
- Git configuration with extensive settings
- tmux configuration
- Dotfiles in `dotfiles/` subdirectory
- CLI tools as Nix packages

### Differences Between Hosts

The two MacBook configurations are intentionally similar. When modifying one, consider whether the change should apply to both. The home-server has a different purpose (NixOS with GNOME desktop, Docker, Mosquitto MQTT, SSH server).

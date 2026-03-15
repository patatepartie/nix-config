# List available recipes
default:
    @just --list

# Update flake inputs
update:
    nix flake update

# Apply configuration for the current machine
switch:
    #!/usr/bin/env bash
    if [ "$(uname)" = "Darwin" ]; then
        sudo darwin-rebuild switch --flake .
    else
        nixos-rebuild switch --sudo --flake .
    fi

# Update flake inputs and apply configuration
upgrade: update switch

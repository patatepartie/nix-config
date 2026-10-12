# List available recipes
default:
    @just --list

# Update flake inputs
update:
    nix flake update

# Apply configuration for the current machine
switch:
    {{ if os() == "macos" { "sudo darwin-rebuild switch --flake ." } else { "nixos-rebuild switch --sudo --flake ." } }}

# Build configuration without applying
build:
    {{ if os() == "macos" { "darwin-rebuild build --flake ." } else { "nixos-rebuild build --sudo --flake ." } }}

# Run the unit tests in hosts/shared/tests
test:
    nix build --no-link -L .#checks.{{ arch() }}-{{ if os() == "macos" { "darwin" } else { "linux" } }}.unknown-warnings

# Update flake inputs and apply configuration
upgrade: update switch

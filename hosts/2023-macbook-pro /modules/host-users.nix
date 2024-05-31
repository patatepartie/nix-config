{ ... }:
let
  username = "cyrilledru";
in
{
  # That's a bit redundant but necessary because of: https://github.com/nix-community/home-manager/issues/4026
  users.users."${username}" = {
    name = username;
    home = "/Users/${username}";
  };

  nix.settings.trusted-users = [ username ];
}

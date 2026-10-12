{ pkgs }:

let
  unknownWarnings = import ../unknown-warnings.nix { inherit pkgs; };
  fixtures = ./unknown-warnings;
in
{
  unknown-warnings = pkgs.runCommand "unknown-warnings-test" { } ''
    ${unknownWarnings} ${fixtures}/rebuild-output.txt ${fixtures}/accepted.txt > actual.txt
    diff -u ${fixtures}/expected.txt actual.txt

    ${unknownWarnings} ${fixtures}/rebuild-output.txt /no/accepted/list > actual-without-list.txt
    diff -u ${fixtures}/expected-without-list.txt actual-without-list.txt

    touch $out
  '';
}

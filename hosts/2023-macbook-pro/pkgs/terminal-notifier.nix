{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
  makeBinaryWrapper,
}:

# Temporary: packages the official prebuilt release instead of pkgs.terminal-notifier.
# 3.0.0 switched to UNUserNotificationCenter, which macOS will only authorize for a
# bundle carrying a valid code-signing identity. Both Homebrew's bottle and the
# nixpkgs source build land unsigned (Identifier=terminal-notifier, Info.plist not
# bound), so authorization is refused; nixpkgs is still on 2.0.0, which hangs.
# See julienXX/terminal-notifier#328.
# Revert once nixpkgs ships a 3.0.0 that preserves or reproduces the release
# signature -- not merely the version bump in NixOS/nixpkgs#555789, which has no
# codesign step and would reintroduce this bug.
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "terminal-notifier";
  version = "3.0.0";

  src = fetchurl {
    url = "https://github.com/julienXX/terminal-notifier/releases/download/${finalAttrs.version}/terminal-notifier-${finalAttrs.version}.zip";
    hash = "sha256-6AT9RyfbLhRs2I7cneufIHpgV0QhLJ7jhkVrVPeijd4=";
  };

  nativeBuildInputs = [
    makeBinaryWrapper
    unzip
  ];

  sourceRoot = ".";

  # Without this, fixup strips and re-signs the binary, destroying the release
  # signature that is the whole point of using the prebuilt zip.
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/Applications
    cp -R terminal-notifier.app $out/Applications/
    # A symlink here makes NSBundle.mainBundle resolve to $out/bin rather than the
    # .app, leaving the process with a null bundle id.
    makeWrapper \
      $out/Applications/terminal-notifier.app/Contents/MacOS/terminal-notifier \
      $out/bin/terminal-notifier

    runHook postInstall
  '';

  meta = {
    description = "Send macOS User Notifications from the command-line";
    homepage = "https://github.com/julienXX/terminal-notifier";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin;
    mainProgram = "terminal-notifier";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})

#!/bin/sh
set -eu

TEMPEST_VERSION=0.2.0
TEMPEST_RELEASE=https://github.com/TempestAI-xyz/tempest-studio/releases/download/v0.2.0

say() { printf '%s\n' "$*"; }
fail() { printf 'Tempest: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "Required command is missing: $1"; }
quote() { printf "'"; printf '%s' "$1" | sed "s/'/'\\\\''/g"; printf "'"; }

cleanup() {
  # Restore the prior Mac application if activation was interrupted.
  if [ -n "$backup" ] && [ -e "$backup" ] && [ ! -e "$target" ] && [ ! -L "$target" ]; then
    if ! mv "$backup" "$target"; then
      printf 'Previous installation retained at: %s\n' "$backup" >&2
      stage=
    fi
  fi
  [ -z "$stage" ] || rm -rf "$stage"
  [ -z "$download_dir" ] || rm -rf "$download_dir"
  if [ -n "$lock_dir" ]; then rmdir "$lock_dir" 2>/dev/null || :; fi
}

verify_download() {
  if command -v sha256sum >/dev/null 2>&1; then
    actual=$(sha256sum "$archive") || fail 'Could not calculate the download checksum.'
  elif command -v shasum >/dev/null 2>&1; then
    actual=$(shasum -a 256 "$archive") || fail 'Could not calculate the download checksum.'
  else
    fail 'SHA-256 verification requires sha256sum or shasum.'
  fi
  actual=${actual%% *}
  [ "$actual" = "$expected" ] || fail 'Download checksum mismatch. Nothing was installed; try again.'
}

prepare_destination() {
  case "$install_dir" in /*) ;; *) fail 'TEMPEST_INSTALL_DIR must be an absolute path.' ;; esac
  mkdir -p "$install_dir"
  # A failed or concurrent installer must not overwrite another installer's work.
  if ! mkdir "$install_dir/.tempest-install.lock" 2>/dev/null; then
    fail "Another install may be running. If none is running, remove $install_dir/.tempest-install.lock and retry."
  fi
  lock_dir=$install_dir/.tempest-install.lock
  stage=$(mktemp -d "$install_dir/.tempest-stage.XXXXXX")
}

install_mac() {
  install_dir=${TEMPEST_INSTALL_DIR:-"$HOME/Applications"}
  need ditto
  if command -v pgrep >/dev/null 2>&1 && pgrep -x Tempest >/dev/null 2>&1; then
    fail 'Quit Tempest before installing or updating it, then run this installer again.'
  fi
  prepare_destination
  ditto -x -k "$archive" "$stage"
  target=$install_dir/Tempest.app
  [ -d "$stage/Tempest.app/Contents/MacOS" ] && [ ! -L "$stage/Tempest.app" ] || fail 'The ZIP does not contain Tempest.app.'
  [ -x "$stage/Tempest.app/Contents/MacOS/Tempest" ] || fail 'The app executable is missing.'
  if [ -L "$target" ]; then fail "The destination is a symbolic link; move it aside first: $target"; fi
  if [ -e "$target" ]; then
    [ -d "$target" ] || fail "The destination is not an application directory: $target"
    backup=$stage/previous.app
    mv "$target" "$backup"
  fi
  mv "$stage/Tempest.app" "$target"
  say "Tempest $TEMPEST_VERSION installed at $target"
  printf 'Launch: open '; quote "$target"; printf '\n'
  say 'This build is unsigned. If macOS blocks launch, attempt opening it, then choose System Settings > Privacy & Security > Open Anyway for Tempest.'
}

install_linux() {
  install_dir=${TEMPEST_INSTALL_DIR:-"${XDG_DATA_HOME:-$HOME/.local/share}/tempest"}
  bin_dir=${TEMPEST_BIN_DIR:-"$HOME/.local/bin"}
  case "$bin_dir" in /*) ;; *) fail 'TEMPEST_BIN_DIR must be an absolute path.' ;; esac
  prepare_destination
  mkdir -p "$bin_dir"
  target=$install_dir/Tempest-$TEMPEST_VERSION.AppImage
  [ ! -d "$target" ] || fail "The application destination is a directory: $target"
  [ ! -d "$bin_dir/tempest" ] || fail "The launcher destination is a directory: $bin_dir/tempest"
  cp "$archive" "$stage/Tempest.AppImage"
  chmod 755 "$stage/Tempest.AppImage"
  mv -f "$stage/Tempest.AppImage" "$target"
  # Use a real shell launcher so paths containing spaces and quotes remain valid.
  launcher=$(mktemp "$bin_dir/.tempest-launcher.XXXXXX")
  {
    printf '#!/bin/sh\nexec '
    quote "$target"
    printf ' "$@"\n'
  } > "$launcher"
  chmod 755 "$launcher"
  mv -f "$launcher" "$bin_dir/tempest"
  say "Tempest $TEMPEST_VERSION installed at $target"
  printf 'Launch: '; quote "$bin_dir/tempest"; printf '\n'
  case ":$PATH:" in
    *":$bin_dir:"*) say 'You can also launch it with: tempest' ;;
    *) printf 'To enable the short command, add this to your shell profile: export PATH='; quote "$bin_dir"; printf ':"$PATH"\n' ;;
  esac
  say 'Requires a graphical Linux session and AppImage/FUSE support, plus the usual Electron/Chromium system libraries.'
}

install_windows() {
  need powershell.exe
  need cygpath
  TEMPEST_INSTALLER_EXE=$(cygpath -w "$archive")
  export TEMPEST_INSTALLER_EXE
  say 'Running the per-user Windows installer…'
  # The native installer owns upgrade handling, shortcuts, and application location.
  powershell.exe -NoProfile -NonInteractive -Command '
    $ErrorActionPreference = "Stop"
    try {
      $process = Start-Process -FilePath $env:TEMPEST_INSTALLER_EXE -ArgumentList "/S" -Wait -PassThru
      if ($process.ExitCode -ne 0) { throw "Installer exited with code $($process.ExitCode)" }
    } catch { Write-Error $_; exit 1 }
  ' </dev/null || fail 'Windows installation did not finish successfully.'
  say "Tempest $TEMPEST_VERSION installed. Launch Tempest from the Start menu."
}

main() {
  download_dir= stage= backup= target= lock_dir=
  trap cleanup 0
  trap 'exit 130' INT
  trap 'exit 143' TERM HUP
  need uname
  need curl
  need mktemp
  os=$(uname -s)
  arch=$(uname -m)
  case "$os" in
    Darwin)
      # uname reports x86_64 when an Apple Silicon Mac uses a Rosetta terminal.
      if [ "$arch" = x86_64 ] && [ "$(sysctl -in sysctl.proc_translated 2>/dev/null || :)" = 1 ]; then arch=arm64; fi
      [ "$arch" = arm64 ] || fail 'This release supports Apple Silicon Macs only; no Intel Mac package is available.'
      platform=mac
      asset=Tempest-$TEMPEST_VERSION-mac-arm64.zip
      expected=c8ff79ee0b85374aad579cc329c80ac7e0e9d9f59f836a7c73990b30a35bb446
      ;;
    Linux)
      case "$(uname -r)" in *[Mm]icrosoft*|*WSL*) fail 'For Windows installation, run this command in Git Bash, not WSL. Native Linux installation requires a Linux desktop.' ;; esac
      case "$arch" in x86_64|amd64) ;; *) fail "No Linux package is available for $arch; this release supports x64 only." ;; esac
      platform=linux
      asset=Tempest-$TEMPEST_VERSION-linux-x86_64.AppImage
      expected=214e788814cfff252e59d37642822142015b5121c7a90a02a3d974736c50c0c6
      ;;
    MINGW*|MSYS*|CYGWIN*)
      # A 32-bit shell can run on 64-bit Windows; use the host architecture first.
      host_arch=${PROCESSOR_ARCHITEW6432:-${PROCESSOR_ARCHITECTURE:-$arch}}
      case "$host_arch" in AMD64|amd64|x86_64) ;; *) fail "No Windows package is available for $host_arch; this release supports x64 only." ;; esac
      platform=windows
      asset=Tempest-$TEMPEST_VERSION-win-x64.exe
      expected=b406be1dbfb2d84cf4a20bc0122ab47e196b2da93481a8974e76abc864564847
      ;;
    *) fail "Unsupported operating system: $os" ;;
  esac
  # HTTPS redirects only; retry transient failures without ever running a partial download.
  download_dir=$(mktemp -d "${TMPDIR:-/tmp}/tempest-download.XXXXXX")
  archive=$download_dir/$asset
  say "Downloading Tempest $TEMPEST_VERSION for $platform ($arch)…"
  curl --fail --location --show-error --silent --retry 3 --connect-timeout 20 --max-time 1800 \
    --proto '=https' --proto-redir '=https' "$TEMPEST_RELEASE/$asset" -o "$archive"
  verify_download
  "install_$platform"
}

# Keep execution last: the complete installer is parsed before piped stdin is used.
main "$@"

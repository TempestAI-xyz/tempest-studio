#!/usr/bin/env bash
set -euo pipefail

TEMPEST_ARCHIVE_URL="https://github.com/gleb-urvanov/tempest-studio/releases/download/v0.1.1/tempest-studio-0.1.1.tgz"
TEMPEST_INSTALL_DIR="${TEMPEST_INSTALL_DIR:-tempest-studio}"
NVM_VERSION="${NVM_VERSION:-v0.40.1}"

ensure_node_20() {
  if command -v node >/dev/null 2>&1; then
    local node_major
    node_major="$(node -p "process.versions.node.split('.')[0]" 2>/dev/null || echo 0)"
    if [ "${node_major:-0}" -ge 20 ]; then
      return
    fi
  fi

  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  if [ ! -s "$NVM_DIR/nvm.sh" ]; then
    echo "Installing nvm into $NVM_DIR..."
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
  fi

  # shellcheck source=/dev/null
  . "$NVM_DIR/nvm.sh"
  nvm install 20
  nvm use 20
}

ensure_node_20

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
archive_path="$tmp_dir/tempest-studio.tgz"

if [ -e "$TEMPEST_INSTALL_DIR" ] && [ ! -d "$TEMPEST_INSTALL_DIR" ]; then
  echo "Install path exists and is not a directory: $TEMPEST_INSTALL_DIR" >&2
  exit 1
fi

echo "Downloading $TEMPEST_ARCHIVE_URL..."
curl -fL "$TEMPEST_ARCHIVE_URL" -o "$archive_path"

mkdir -p "$TEMPEST_INSTALL_DIR"
tar -xzf "$archive_path" -C "$TEMPEST_INSTALL_DIR" --strip-components=1

echo "Tempest Studio installed in $TEMPEST_INSTALL_DIR"
echo "Start it with:"
echo "  cd $TEMPEST_INSTALL_DIR && npm start"

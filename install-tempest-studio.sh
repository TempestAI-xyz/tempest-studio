#!/usr/bin/env bash
set -euo pipefail

TEMPEST_INSTALL_DIR="${TEMPEST_INSTALL_DIR:-tempest-studio}"
NVM_VERSION="${NVM_VERSION:-v0.40.1}"
TEMPEST_ARCHIVE_URL="https://github.com/gleb-urvanov/tempest-studio/releases/download/v0.1.2/tempest-studio-0.1.2.tgz"
TEMPEST_RELEASE_API_URL="${TEMPEST_RELEASE_API_URL:-https://api.github.com/repos/gleb-urvanov/tempest-studio/releases/latest}"

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

resolve_archive_url() {
  if [ -n "$TEMPEST_ARCHIVE_URL" ]; then
    printf '%s' "$TEMPEST_ARCHIVE_URL"
    return
  fi

  curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$TEMPEST_RELEASE_API_URL" |
    node -e '
      const fs = require("node:fs");
      const release = JSON.parse(fs.readFileSync(0, "utf8"));
      const assets = Array.isArray(release.assets) ? release.assets : [];
      const candidates = assets
        .filter((asset) => /^tempest-studio-\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?\.tgz$/.test(String(asset.name || "")))
        .sort((left, right) => String(right.created_at || "").localeCompare(String(left.created_at || "")));
      const archiveUrl = String(candidates[0]?.browser_download_url || "");
      if (!archiveUrl) {
        console.error("The latest Tempest Studio release has no versioned .tgz asset.");
        process.exit(1);
      }
      process.stdout.write(archiveUrl);
    '
}

ensure_node_20
TEMPEST_ARCHIVE_URL="$(resolve_archive_url)"

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

echo "Installing production dependencies and Chromium..."
(
  cd "$TEMPEST_INSTALL_DIR"
  npm install --omit=dev --no-audit --no-fund
  npm run browser:check -- --local
)

echo "Tempest Studio installed in $TEMPEST_INSTALL_DIR"
echo "Start it with:"
echo "  cd $TEMPEST_INSTALL_DIR && npm start"

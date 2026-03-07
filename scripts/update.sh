#!/usr/bin/env bash
set -euo pipefail

readonly GITHUB_REPO="pingdotgg/t3code"
readonly NPM_PACKAGE_NAME="t3"
readonly NPM_REGISTRY_URL="https://registry.npmjs.org"
readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly TMP_DIR="${ROOT_DIR}/.tmp"
readonly XDG_CACHE_HOME="${TMP_DIR}/cache"
export XDG_CACHE_HOME

log() {
  printf '[t3code-nix] %s\n' "$1"
}

fail() {
  printf '[t3code-nix] error: %s\n' "$1" >&2
  exit 1
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required tool: $1"
}

ensure_repo_root() {
  cd "$ROOT_DIR"
  [ -f flake.nix ] || fail "run from repository root"
  [ -f package.nix ] || fail "run from repository root"
  [ -f package-cli.nix ] || fail "run from repository root"
  mkdir -p "$TMP_DIR" "$XDG_CACHE_HOME"
}

current_desktop_version() {
  sed -n 's/.*version = "\([^"]*\)".*/\1/p' package.nix | head -1
}

latest_release_json() {
  curl -sSfL "https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
}

release_version_from_json() {
  jq -r '.tag_name' | sed 's/^v//'
}

appimage_asset_from_json() {
  jq -r '.assets[] | select(.name | endswith("-x86_64.AppImage")) | @base64' | head -n 1
}

asset_field() {
  local asset="$1"
  local field="$2"
  printf '%s' "$asset" | base64 --decode | jq -r "$field"
}

github_digest_to_sri() {
  local digest="$1"
  local algo hex
  algo="${digest%%:*}"
  hex="${digest#*:}"
  [ "$algo" = "sha256" ] || fail "unsupported digest algorithm: ${algo}"
  nix hash convert --hash-algo sha256 --to sri "$hex"
}

npm_metadata() {
  local version="$1"
  curl -sSfL "${NPM_REGISTRY_URL}/${NPM_PACKAGE_NAME}/${version}"
}

write_upstream_cli_package_files() {
  local version="$1"
  local tmpdir
  tmpdir="$(mktemp -d "${TMP_DIR}/update.XXXXXX")"
  trap 'rm -rf "$tmpdir"' RETURN

  log "downloading npm tarball for ${version}"
  curl -sSfL "${NPM_REGISTRY_URL}/${NPM_PACKAGE_NAME}/-/${NPM_PACKAGE_NAME}-${version}.tgz" -o "$tmpdir/package.tgz"
  tar -xzf "$tmpdir/package.tgz" -C "$tmpdir"

  mkdir -p npm
  cp "$tmpdir/package/package.json" npm/package.json

  log "generating package-lock.json for ${version}"
  (
    cd "$tmpdir/package"
    npm install --package-lock-only --ignore-scripts >/dev/null
  )
  cp "$tmpdir/package/package-lock.json" npm/package-lock.json
}

update_desktop_package() {
  local version="$1"
  local hash="$2"

  sed -i "s|version = \".*\";|version = \"${version}\";|" package.nix
  sed -i "s|hash = \".*\";|hash = \"${hash}\";|" package.nix
}

update_cli_package() {
  local version="$1"
  local hash="$2"

  sed -i "s|version = \".*\";|version = \"${version}\";|" package-cli.nix
  sed -i "s|hash = \".*\";|hash = \"${hash}\";|" package-cli.nix
}

validate() {
  log "validating flake"
  nix flake check
  nix build .#t3code
  test -x ./result/bin/t3code
  nix build .#t3code-cli
  ./result/bin/t3 --help >/dev/null
}

usage() {
  cat <<'USAGE'
Usage: ./scripts/update.sh [--check] [--version X.Y.Z]

Options:
  --check          Exit with status 1 if an update is available.
  --version VALUE  Update to the specified version instead of latest release.
  --help           Show this message.
USAGE
}

main() {
  local check_only=false
  local target_version=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --check)
        check_only=true
        shift
        ;;
      --version)
        [ "$#" -ge 2 ] || fail "--version requires a value"
        target_version="$2"
        shift 2
        ;;
      --help)
        usage
        exit 0
        ;;
      *)
        fail "unknown argument: $1"
        ;;
    esac
  done

  ensure_repo_root
  require_tool base64
  require_tool curl
  require_tool jq
  require_tool nix
  require_tool npm
  require_tool tar

  local release_json current latest asset desktop_digest desktop_hash cli_metadata cli_hash
  current="$(current_desktop_version)"
  release_json="$(latest_release_json)"
  latest="${target_version:-$(printf '%s' "$release_json" | release_version_from_json)}"

  log "current desktop version: ${current}"
  log "target version: ${latest}"

  if [ "$current" = "$latest" ]; then
    log "already up to date"
    exit 0
  fi

  if [ "$check_only" = true ]; then
    log "update available: ${current} -> ${latest}"
    exit 1
  fi

  if [ -n "$target_version" ]; then
    release_json="$(curl -sSfL "https://api.github.com/repos/${GITHUB_REPO}/releases/tags/v${latest}")"
  fi

  asset="$(printf '%s' "$release_json" | appimage_asset_from_json)"
  [ -n "$asset" ] || fail "failed to find an x86_64 AppImage asset for ${latest}"

  desktop_digest="$(asset_field "$asset" '.digest')"
  [ "$desktop_digest" != "null" ] || fail "failed to read GitHub digest for AppImage ${latest}"
  desktop_hash="$(github_digest_to_sri "$desktop_digest")"

  cli_metadata="$(npm_metadata "$latest")"
  cli_hash="$(printf '%s' "$cli_metadata" | jq -r '.dist.integrity')"
  [ "$cli_hash" != "null" ] || fail "failed to find npm dist.integrity for ${latest}"

  update_desktop_package "$latest" "$desktop_hash"
  write_upstream_cli_package_files "$latest"
  update_cli_package "$latest" "$cli_hash"
  validate

  log "updated desktop and CLI packages to ${latest}"
}

main "$@"

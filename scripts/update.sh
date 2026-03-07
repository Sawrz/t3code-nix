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
  mkdir -p "$TMP_DIR"
  mkdir -p "$XDG_CACHE_HOME"
}

current_version() {
  sed -n 's/.*version = "\([^"]*\)".*/\1/p' package.nix | head -1
}

latest_release_version() {
  curl -sSfL "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" | jq -r '.tag_name' | sed 's/^v//'
}

npm_metadata() {
  local version="$1"
  curl -sSfL "${NPM_REGISTRY_URL}/${NPM_PACKAGE_NAME}/${version}"
}

write_upstream_package_files() {
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

update_package_nix() {
  local version="$1"
  local hash="$2"

  sed -i "s|version = \".*\";|version = \"${version}\";|" package.nix
  sed -i "s|hash = \".*\";|hash = \"${hash}\";|" package.nix
}

validate() {
  log "validating flake"
  nix flake check
  nix build .#t3
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
  require_tool curl
  require_tool jq
  require_tool npm
  require_tool nix

  local current latest metadata integrity
  current="$(current_version)"
  latest="${target_version:-$(latest_release_version)}"

  log "current version: ${current}"
  log "target version: ${latest}"

  if [ "$current" = "$latest" ]; then
    log "already up to date"
    exit 0
  fi

  if [ "$check_only" = true ]; then
    log "update available: ${current} -> ${latest}"
    exit 1
  fi

  metadata="$(npm_metadata "$latest")"
  integrity="$(printf '%s' "$metadata" | jq -r '.dist.integrity')"
  [ "$integrity" != "null" ] || fail "failed to find dist.integrity for ${latest}"

  write_upstream_package_files "$latest"
  update_package_nix "$latest" "$integrity"
  validate

  log "updated to ${latest}"
}

main "$@"

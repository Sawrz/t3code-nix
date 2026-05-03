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
  github_api_get "https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
}

github_api_get() {
  local url="$1"
  local -a curl_args=(
    -sSfL
    -H "Accept: application/vnd.github+json"
    -H "X-GitHub-Api-Version: 2022-11-28"
    -H "User-Agent: t3code-nix-update-script"
  )

  if [ -n "${GH_UPDATE_TOKEN:-}" ]; then
    curl_args+=(-H "Authorization: Bearer ${GH_UPDATE_TOKEN}")
  fi

  curl "${curl_args[@]}" "$url"
}

release_version_from_json() {
  jq -r '.tag_name' | sed 's/^v//'
}

asset_from_json() {
  local suffix="$1"
  jq -r --arg suffix "$suffix" '.assets[] | select(.name | endswith($suffix)) | @base64' | head -n 1
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

release_assets_ready() {
  local release_json="$1"
  local asset digest

  for suffix in '-x86_64.AppImage' '-x64.zip' '-arm64.zip'; do
    asset="$(printf '%s' "$release_json" | asset_from_json "$suffix")"
    [ -n "$asset" ] || return 1

    digest="$(asset_field "$asset" '.digest')"
    [ -n "$digest" ] || return 1
    [ "$digest" != "null" ] || return 1
  done
}

cli_package_ready() {
  local version="$1"
  local metadata tarball integrity

  metadata="$(npm_metadata "$version" 2>/dev/null)" || return 1
  tarball="$(printf '%s' "$metadata" | jq -r '.dist.tarball')"
  integrity="$(printf '%s' "$metadata" | jq -r '.dist.integrity')"

  [ -n "$tarball" ] || return 1
  [ "$tarball" != "null" ] || return 1
  [ -n "$integrity" ] || return 1
  [ "$integrity" != "null" ] || return 1

  curl -sSfLI "$tarball" >/dev/null
}

version_is_ready() {
  local release_json="$1"
  local version="$2"

  release_assets_ready "$release_json" && cli_package_ready "$version"
}

write_upstream_cli_package_files() {
  local version="$1"
  local tmpdir
  tmpdir="$(mktemp -d "${TMP_DIR}/update.XXXXXX")"
  trap 'rm -rf -- "$tmpdir"; trap - RETURN' RETURN

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
  local linux_hash="$2"
  local darwin_x64_hash="$3"
  local darwin_arm64_hash="$4"

  sed -i "s|version = \".*\";|version = \"${version}\";|" package.nix
  sed -i "s|linuxHash = \".*\";|linuxHash = \"${linux_hash}\";|" package.nix
  sed -i "s|darwinX64Hash = \".*\";|darwinX64Hash = \"${darwin_x64_hash}\";|" package.nix
  sed -i "s|darwinArm64Hash = \".*\";|darwinArm64Hash = \"${darwin_arm64_hash}\";|" package.nix
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
  nix eval .#packages.x86_64-darwin.t3code.drvPath >/dev/null
  nix eval .#packages.aarch64-darwin.t3code.drvPath >/dev/null
  nix eval .#packages.x86_64-darwin.t3code-cli.drvPath >/dev/null
  nix eval .#packages.aarch64-darwin.t3code-cli.drvPath >/dev/null
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

  local release_json current latest linux_asset darwin_x64_asset darwin_arm64_asset
  local linux_digest darwin_x64_digest darwin_arm64_digest
  local linux_hash darwin_x64_hash darwin_arm64_hash cli_metadata cli_hash
  current="$(current_desktop_version)"
  release_json="$(latest_release_json)"
  latest="${target_version:-$(printf '%s' "$release_json" | release_version_from_json)}"

  log "current desktop version: ${current}"
  log "target version: ${latest}"

  if [ "$current" = "$latest" ]; then
    log "already up to date"
    exit 0
  fi

  if [ -n "$target_version" ]; then
    release_json="$(github_api_get "https://api.github.com/repos/${GITHUB_REPO}/releases/tags/v${latest}")"
  fi

  if [ "$check_only" = true ]; then
    if ! version_is_ready "$release_json" "$latest"; then
      log "upstream artifacts for ${latest} are not ready yet"
      exit 0
    fi

    log "update available: ${current} -> ${latest}"
    exit 1
  fi

  linux_asset="$(printf '%s' "$release_json" | asset_from_json '-x86_64.AppImage')"
  [ -n "$linux_asset" ] || fail "failed to find an x86_64 AppImage asset for ${latest}"

  darwin_x64_asset="$(printf '%s' "$release_json" | asset_from_json '-x64.zip')"
  [ -n "$darwin_x64_asset" ] || fail "failed to find an x64 Darwin zip asset for ${latest}"

  darwin_arm64_asset="$(printf '%s' "$release_json" | asset_from_json '-arm64.zip')"
  [ -n "$darwin_arm64_asset" ] || fail "failed to find an arm64 Darwin zip asset for ${latest}"

  linux_digest="$(asset_field "$linux_asset" '.digest')"
  [ "$linux_digest" != "null" ] || fail "failed to read GitHub digest for Linux AppImage ${latest}"
  linux_hash="$(github_digest_to_sri "$linux_digest")"

  darwin_x64_digest="$(asset_field "$darwin_x64_asset" '.digest')"
  [ "$darwin_x64_digest" != "null" ] || fail "failed to read GitHub digest for Darwin x64 zip ${latest}"
  darwin_x64_hash="$(github_digest_to_sri "$darwin_x64_digest")"

  darwin_arm64_digest="$(asset_field "$darwin_arm64_asset" '.digest')"
  [ "$darwin_arm64_digest" != "null" ] || fail "failed to read GitHub digest for Darwin arm64 zip ${latest}"
  darwin_arm64_hash="$(github_digest_to_sri "$darwin_arm64_digest")"

  cli_metadata="$(npm_metadata "$latest")"
  cli_hash="$(printf '%s' "$cli_metadata" | jq -r '.dist.integrity')"
  [ "$cli_hash" != "null" ] || fail "failed to find npm dist.integrity for ${latest}"

  update_desktop_package "$latest" "$linux_hash" "$darwin_x64_hash" "$darwin_arm64_hash"
  write_upstream_cli_package_files "$latest"
  update_cli_package "$latest" "$cli_hash"
  validate

  log "updated desktop and CLI packages to ${latest}"
}

main "$@"

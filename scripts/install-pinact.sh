#!/usr/bin/env bash
# Install one pinned pinact release on a Linux GitHub Actions runner, verifying
# the archive against the checksum recorded here, and put it on PATH.
#
# The version and both checksums come from the upstream release's
# pinact_<version>_checksums.txt; bump all three together.
#
# Usage: install-pinact.sh [<install-dir>]   (default: $RUNNER_TEMP/pinact or a temp dir)

set -euo pipefail

version=5.0.0
declare -A checksums=(
  [amd64]=d005bbb85da80dacdc07816f24a5da723a9f6d1e9f3d3e7e73df33f9caa1358f
  [arm64]=d28ca5e9ddd7950da4a808288f8a83f84fc3ca40e86bab970f3adeef33578c0b
)

case "$(uname -m)" in
  x86_64) arch=amd64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *)
    echo "install-pinact: unsupported architecture $(uname -m)" >&2
    exit 1
    ;;
esac
[[ "$(uname -s)" == Linux ]] || {
  echo "install-pinact: this installer covers Linux runners only" >&2
  exit 1
}

dir=${1:-${RUNNER_TEMP:-$(mktemp -d)}/pinact}
mkdir -p "$dir"
archive="pinact_linux_${arch}.tar.gz"

curl --fail --silent --show-error --location \
  --output "$dir/$archive" \
  "https://github.com/suzuki-shunsuke/pinact/releases/download/v${version}/${archive}"
printf '%s  %s\n' "${checksums[$arch]}" "$dir/$archive" | sha256sum --check --quiet
tar -xzf "$dir/$archive" -C "$dir" pinact
rm -f "$dir/$archive"

"$dir/pinact" version >/dev/null
if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "$dir" >>"$GITHUB_PATH"
fi
echo "$dir/pinact"

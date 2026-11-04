#!/usr/bin/env bash
# The one step of action.yml: resolve the version, download, verify, unpack, check, add to PATH.
# Reads INPUT_VERSION, INPUT_VARIANT, LOOKUP_TOKEN and the runner's RUNNER_*, GITHUB_OUTPUT and GITHUB_PATH.
set -euo pipefail

releases=https://github.com/ru551n/yavs/releases
guide=https://yavs.readthedocs.io/en/latest/install.html

fail() {
  local msg="$1"
  msg=${msg//%/%25}
  msg=${msg//$'\r'/%0D}
  msg=${msg//$'\n'/%0A}
  echo "::error title=yavs-action::$msg"
  exit 1
}

# fetch URL FILE: the HTTP status in $status; a transport failure stops here, naming cause and fix.
fetch() {
  local rc=0
  status=$(curl -sSL --retry 3 --retry-connrefused -o "$2" -w '%{http_code}' "$1") || rc=$?
  [ "$rc" = 0 ] || fail "could not download $1: curl exit status $rc. Re-run the job; if it keeps failing, check that the runner can reach github.com."
}

# Stable means a plain vX.Y.Z tag: all yavs releases carry GitHub's pre-release mark while yavs is
# early, so the mark cannot tell. The vunit-yavs-v* and vscode-v* tags are other products.
# ponytail: reads the newest 100 releases, enough while a page holds at least one stable release.
latest_version() {
  local json="$1/releases.json" rc=0
  status=$(
    if [ -n "${LOOKUP_TOKEN:-}" ]; then
      printf 'header = "Authorization: Bearer %s"\n' "$LOOKUP_TOKEN"
    fi | curl -sSL --retry 3 --retry-connrefused --config - -o "$json" -w '%{http_code}' \
      "https://api.github.com/repos/ru551n/yavs/releases?per_page=100"
  ) || rc=$?
  [ "$rc" = 0 ] || fail "could not look up the latest yavs release: curl exit status $rc. Re-run the job, or set version to an exact version such as 0.11.0, which needs no lookup."
  [ "$status" = 200 ] || fail "could not look up the latest yavs release: api.github.com answered HTTP $status (403 or 429 is its rate limit). Re-run the job later, or set version to an exact version such as 0.11.0, which needs no lookup."
  version=$(grep -oE '"tag_name": *"v[0-9]+\.[0-9]+\.[0-9]+"' "$json" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -n 1) \
    || fail "no stable yavs release found at $releases. Set version to an exact version listed there."
}

case "${RUNNER_OS:-}-${RUNNER_ARCH:-}" in
  Linux-X64) target=x86_64-unknown-linux-gnu ext=tar.gz unpacker=tar ;;
  Linux-ARM64) target=aarch64-unknown-linux-gnu ext=tar.gz unpacker=tar ;;
  Windows-X64) target=x86_64-pc-windows-msvc ext=zip unpacker=unzip ;;
  *) fail "no yavs archive for ${RUNNER_OS:-unknown OS} ${RUNNER_ARCH:-unknown architecture}: there are archives for Linux x86_64, Linux aarch64 and Windows x86_64. Use one of those runners, or build yavs from source ($guide)." ;;
esac

for tool in curl grep sort sha256sum "$unpacker"; do
  command -v "$tool" > /dev/null || fail "this runner has no $tool, which yavs-action needs. Install it in an earlier step."
done

requested=${INPUT_VERSION:-}
version=${requested#v}
variant=${INPUT_VARIANT:-default}
case "$variant" in
  default | compat) ;;
  *) fail "variant '$variant' is not a variant. The valid values are default and compat." ;;
esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if [ "$requested" = latest ]; then
  latest_version "$tmp"
elif ! [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  fail "version '$requested' is not a version. Write an exact version such as 0.11.0, or latest."
fi

# compat is the archive for CPUs without AVX2: the x86_64 targets have one from yavs 0.14.0,
# aarch64 has only one archive.
suffix=
if [ "$variant" = compat ]; then
  case "$target" in
    aarch64-*) echo "::notice title=yavs-action::variant compat on $target: the only archive there is installed, as for default." ;;
    *)
      [ "$(printf '%s\n0.14.0\n' "${version%%-*}" | sort -V | head -n 1)" = 0.14.0 ] \
        || fail "variant compat needs yavs 0.14.0 or newer: v$version has no compat archive. Set version to 0.14.0 or newer, or variant to default."
      suffix=-compat ;;
  esac
fi

name="yavs-$version-$target$suffix"
base="$releases/download/v$version"

fetch "$base/SHA256SUMS" "$tmp/SHA256SUMS"
case "$status" in
  200) ;;
  404) fail "there is no yavs release v$version. Set version to a version listed at $releases, or to latest." ;;
  *) fail "could not download $base/SHA256SUMS: HTTP $status. Re-run the job; if it keeps failing, check $releases and the runner's access to github.com." ;;
esac
fetch "$base/$name.$ext" "$tmp/$name.$ext"
case "$status" in
  200) ;;
  404) fail "yavs release v$version has no archive $name.$ext for this runner. Set version to a release at $releases that has one." ;;
  *) fail "could not download $base/$name.$ext: HTTP $status. Re-run the job; if it keeps failing, check $releases and the runner's access to github.com." ;;
esac

grep -F "  $name.$ext" "$tmp/SHA256SUMS" > "$tmp/want" \
  || fail "SHA256SUMS of yavs v$version does not list $name.$ext, so it cannot be verified. Set version to another release at $releases."
(cd "$tmp" && sha256sum -c want > /dev/null 2>&1) \
  || fail "$name.$ext does not match its SHA256SUMS line: the download is damaged or was changed. Re-run the job; if it keeps failing, report it at https://github.com/ru551n/yavs/issues."

tool_cache=${RUNNER_TOOL_CACHE:-$tmp}
if [ "$RUNNER_OS" = Windows ]; then
  tool_cache=$(cygpath -m "$tool_cache")
fi
dir="$tool_cache/yavs/$version/$target$suffix"
rm -rf "$dir"
mkdir -p "$dir"
if [ "$ext" = zip ]; then
  unzip -q "$tmp/$name.zip" -d "$dir" || fail "could not unpack $name.zip into $dir. Check the runner's free disk space and re-run."
else
  tar xzf "$tmp/$name.tar.gz" -C "$dir" || fail "could not unpack $name.tar.gz into $dir. Check the runner's free disk space and re-run."
fi

bin="$dir/$name"
said=$("$bin/yavs" --version 2>&1) \
  || fail "yavs $version does not run on this runner: ${said:-no output}. Its requirements are at $guide."
case "$said" in
  "yavs $version" | "yavs $version "*) ;;
  *) fail "asked for yavs $version, but the archive's yavs --version says: $said. Report it at https://github.com/ru551n/yavs/issues." ;;
esac
echo "$said"

if [ "$RUNNER_OS" = Windows ]; then
  bin=$(cygpath -w "$bin")
fi
echo "$bin" >> "$GITHUB_PATH"
{
  echo "version=$version"
  echo "path=$bin"
} >> "$GITHUB_OUTPUT"

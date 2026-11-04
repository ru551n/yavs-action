#!/usr/bin/env bash
# Every error of install.sh and the version selection, with curl, tar and unzip stubbed.
# Nothing here touches the network. The real downloads are in .github/workflows/ci.yml.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/stub" "$work/empty"

cat > "$work/stub/curl" <<'STUB'
#!/usr/bin/env bash
[ -z "${STUB_EXIT:-}" ] || exit "$STUB_EXIT"
while [ $# -gt 1 ]; do
  case "$1" in
    --config) cat > /dev/null; shift ;;
    -o) out=$2; shift ;;
  esac
  shift
done
url=$1
case "$url" in
  *api.github.com*)
    printf '%s' "${STUB_JSON:-}" > "$out"
    printf '%s' "${STUB_API:-200}" ;;
  *SHA256SUMS)
    v=${url%/SHA256SUMS}; v=${v##*/v}
    hash=$(printf archive | sha256sum | cut -d' ' -f1)
    printf '%s  %s\n' "$hash" "${STUB_LISTED:-yavs-$v-x86_64-unknown-linux-gnu${STUB_SUFFIX:-}.tar.gz}" > "$out"
    if [ -n "${STUB_DAMAGED:-}" ]; then
      printf '%s  %s\n' 0000 "yavs-$v-x86_64-unknown-linux-gnu.tar.gz" > "$out"
    fi
    printf '%s' "${STUB_SUMS:-200}" ;;
  *)
    printf archive > "$out"
    printf '%s' "${STUB_ARCHIVE:-200}" ;;
esac
STUB

cat > "$work/stub/tar" <<'STUB'
#!/usr/bin/env bash
name=$(basename "$2" .tar.gz)
v=${name#yavs-}; v=${v%%-x86_64-unknown-linux-gnu*}; v=${v%%-aarch64-unknown-linux-gnu*}
mkdir -p "$4/$name"
printf '#!/bin/sh\n%s\n' "${STUB_YAVS:-echo yavs $v \(stub\)}" > "$4/$name/yavs"
chmod +x "$4/$name/yavs"
STUB
chmod +x "$work/stub/curl" "$work/stub/tar"

fails=0
run() {
  : > "$work/output"
  : > "$work/path"
  env PATH="$work/stub:$PATH" RUNNER_OS=Linux RUNNER_ARCH=X64 RUNNER_TOOL_CACHE="$work/tools" \
    GITHUB_OUTPUT="$work/output" GITHUB_PATH="$work/path" LOOKUP_TOKEN=token "$@" \
    "$BASH" "$root/install.sh" 2>&1
}

# rejects NAME CAUSE FIX VAR=VALUE...: exits non-zero, and the error names the cause and the fix.
rejects() {
  local name=$1 cause=$2 fix=$3 out rc=0
  shift 3
  out=$(run "$@") || rc=$?
  if [ "$rc" = 0 ] || [[ $out != *"::error"*"$cause"*"$fix"* ]]; then
    echo "FAIL $name: exit status $rc, output: $out"
    fails=$((fails + 1))
  else
    echo "ok   $name"
  fi
}

# installs NAME VERSION VAR=VALUE...: succeeds and reports that version on PATH and in the outputs.
# EXPECT_TARGET, EXPECT_SUFFIX (the archive's variant) and EXPECT_OUT (text of the log) can be set.
installs() {
  local name=$1 want=$2 out rc=0 dir t=${EXPECT_TARGET:-x86_64-unknown-linux-gnu} s=${EXPECT_SUFFIX:-}
  shift 2
  out=$(run "$@") || rc=$?
  dir="$work/tools/yavs/$want/$t$s/yavs-$want-$t$s"
  if [[ $out != *"${EXPECT_OUT:-}"* ]]; then
    echo "FAIL $name: output lacks '$EXPECT_OUT': $out"
    fails=$((fails + 1))
  elif [ "$rc" != 0 ] || [ "$(cat "$work/path")" != "$dir" ] \
    || [ "$(cat "$work/output")" != "version=$want"$'\n'"path=$dir" ]; then
    echo "FAIL $name: exit status $rc, output: $out, PATH line: $(cat "$work/path")"
    fails=$((fails + 1))
  else
    echo "ok   $name"
  fi
}

releases='[{"tag_name":"vscode-v9.0.0"},{"tag_name": "vunit-yavs-v8.0.0"},{"tag_name":"v0.11.0-rc1"},{"tag_name":"v0.9.0"},{"tag_name":"v0.10.0"}]'

installs "exact version" 1.2.3 INPUT_VERSION=1.2.3
installs "exact version with v" 1.2.3 INPUT_VERSION=v1.2.3
installs "exact pre-release version" 1.2.3-rc1 INPUT_VERSION=1.2.3-rc1
installs "latest is the highest stable tag of yavs itself" 0.10.0 INPUT_VERSION=latest "STUB_JSON=$releases"

EXPECT_SUFFIX=-compat STUB_SUFFIX=-compat installs "compat" 0.14.0 INPUT_VERSION=0.14.0 INPUT_VARIANT=compat
EXPECT_SUFFIX=-compat STUB_SUFFIX=-compat installs "compat, newer version" 1.2.3 INPUT_VERSION=v1.2.3 INPUT_VARIANT=compat
installs "variant default" 0.14.0 INPUT_VERSION=0.14.0 INPUT_VARIANT=default
installs "variant default on an old version" 0.10.0 INPUT_VERSION=0.10.0 INPUT_VARIANT=default
EXPECT_SUFFIX=-compat STUB_SUFFIX=-compat installs "compat, latest" 0.14.0 INPUT_VERSION=latest INPUT_VARIANT=compat \
  'STUB_JSON=[{"tag_name":"v0.14.0"},{"tag_name":"v0.9.0"}]'
EXPECT_TARGET=aarch64-unknown-linux-gnu EXPECT_OUT="::notice" STUB_LISTED=yavs-0.14.0-aarch64-unknown-linux-gnu.tar.gz \
  installs "compat on aarch64 installs the one archive, with a notice" 0.14.0 INPUT_VERSION=0.14.0 INPUT_VARIANT=compat RUNNER_ARCH=ARM64
EXPECT_TARGET=aarch64-unknown-linux-gnu STUB_LISTED=yavs-0.10.0-aarch64-unknown-linux-gnu.tar.gz \
  installs "compat on aarch64 needs no new version" 0.10.0 INPUT_VERSION=0.10.0 INPUT_VARIANT=compat RUNNER_ARCH=ARM64

rejects "unknown variant" "variant 'fast' is not a variant" "default and compat" INPUT_VERSION=1.2.3 INPUT_VARIANT=fast
rejects "variant in capitals" "variant 'Compat' is not a variant" "default and compat" INPUT_VERSION=1.2.3 INPUT_VARIANT=Compat
rejects "compat before 0.14.0" "variant compat needs yavs 0.14.0 or newer: v0.13.2" "variant to default" INPUT_VERSION=0.13.2 INPUT_VARIANT=compat
rejects "compat before 0.14.0, one digit" "variant compat needs yavs 0.14.0 or newer: v0.9.0" "variant to default" INPUT_VERSION=0.9.0 INPUT_VARIANT=compat
rejects "compat, latest is too old" "variant compat needs yavs 0.14.0 or newer: v0.10.0" "variant to default" INPUT_VERSION=latest INPUT_VARIANT=compat "STUB_JSON=$releases"
rejects "unsupported platform" "no yavs archive for macOS ARM64" "Linux x86_64" INPUT_VERSION=1.2.3 RUNNER_OS=macOS RUNNER_ARCH=ARM64
rejects "unsupported architecture" "no yavs archive for Windows ARM64" "build yavs from source" INPUT_VERSION=1.2.3 RUNNER_OS=Windows RUNNER_ARCH=ARM64
rejects "not a version" "version 'lastest' is not a version" "or latest" INPUT_VERSION=lastest
rejects "empty version" "version '' is not a version" "or latest" INPUT_VERSION=
rejects "path in the version" "is not a version" "or latest" INPUT_VERSION=1.2.3/../x
rejects "unknown version" "no yavs release v9.9.9" "or to latest" INPUT_VERSION=9.9.9 STUB_SUMS=404
rejects "no archive for this runner" "has no archive yavs-1.2.3-x86_64" "that has one" INPUT_VERSION=1.2.3 STUB_ARCHIVE=404
rejects "server error on SHA256SUMS" "HTTP 503" "Re-run" INPUT_VERSION=1.2.3 STUB_SUMS=503
rejects "server error on the archive" "HTTP 500" "Re-run" INPUT_VERSION=1.2.3 STUB_ARCHIVE=500
rejects "failed download" "curl exit status 7" "Re-run" INPUT_VERSION=1.2.3 STUB_EXIT=7
rejects "archive not listed" "does not list" "another release" INPUT_VERSION=1.2.3 STUB_LISTED=other
rejects "checksum mismatch" "does not match" "Re-run" INPUT_VERSION=1.2.3 STUB_DAMAGED=1
rejects "wrong version in the archive" "--version says: yavs 0.0.1" "Report" INPUT_VERSION=1.2.3 "STUB_YAVS=echo yavs 0.0.1"
rejects "version only as a prefix" "--version says: yavs 1.2.30" "Report" INPUT_VERSION=1.2.3 "STUB_YAVS=echo yavs 1.2.30"
rejects "yavs does not run" "does not run on this runner" "requirements" INPUT_VERSION=1.2.3 "STUB_YAVS=exit 126"
rejects "latest, rate limited" "HTTP 403" "exact version" INPUT_VERSION=latest STUB_API=403
rejects "latest, no network" "curl exit status 6" "exact version" INPUT_VERSION=latest STUB_EXIT=6
rejects "latest, no stable release" "no stable yavs release" "exact version" INPUT_VERSION=latest 'STUB_JSON=[{"tag_name":"vscode-v0.1.0"}]'
rejects "missing tool" "has no curl" "earlier step" INPUT_VERSION=1.2.3 PATH="$work/empty"

[ "$fails" = 0 ] || { echo "$fails failed"; exit 1; }
echo "all passed"

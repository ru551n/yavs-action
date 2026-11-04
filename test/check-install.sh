#!/usr/bin/env bash
# check-install.sh VERSION OUTPUT_VERSION OUTPUT_PATH [BUILD]: the yavs on PATH is the one asked for and
# the action said it installed, and it runs a small design to its expected result. Given BUILD,
# the Build line of --version must say it.
set -euo pipefail

want=$1 output_version=$2 output_path=$3 build=${4:-}
here=$(cd "$(dirname "$0")" && pwd)

[ "$output_version" = "$want" ] || { echo "output version is $output_version, wanted $want"; exit 1; }
said=$(yavs --version | tr -d '\r')$'\n'
echo "$said"
case "$said" in
  "yavs $want "*) ;;
  *) echo "yavs --version does not name $want"; exit 1 ;;
esac

if [ -n "$build" ]; then
  case "$said" in
    *$'\n'"Build: $build"$'\n'*) ;;
    *) echo "yavs --version has no line 'Build: $build'"; exit 1 ;;
  esac
fi

found=$(dirname "$(command -v yavs)")
if command -v cygpath > /dev/null; then
  output_path=$(cygpath -u "$output_path")
fi
[ "$found" = "$output_path" ] || { echo "yavs comes from $found, the action installed to $output_path"; exit 1; }

work=$(mktemp -d)
yavs analyze --work="work:$work/work" "$here/hello_tb.vhd"
result=$(yavs run --work="work:$work/work" hello_tb 2>&1)
echo "$result"
case "$result" in
  *"hello, count is 3"*) ;;
  *) echo "the design did not report its result"; exit 1 ;;
esac
rm -rf "$work"

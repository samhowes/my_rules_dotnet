#!/bin/bash
set -e
if [[ ! -f WORKSPACE ]]; then echo >&2 "not at root"; exit 1; fi

arg_string=" $* "
target="${1/\/\//}"
# shellcheck disable=SC2199
if [[ -n "${target:-}" && ! "$arg_string" =~ "--no_build" ]]; then
  set +e
  bazel build --define=BUILD_DIAG=1 "//$target"
  set -e
fi

tmp="$(pwd)/tmp"

if [[ -d "$tmp" ]]; then rm -rf "$tmp"; fi

mkdir "$tmp"
pushd bazel-bin

if [[ "$target" == *":"* ]]; then
  pkg="$(dirname "${target/://}")"
else
  pkg="$target"
fi
# shellcheck disable=SC2207
input=($(find "$pkg"/* -name "*.dot" -not \( -path '*runfiles/*' \)))
for i in "${input[@]}"
do
  src="$i"
  dest="$tmp/$src.svg"
  echo "$src"
  mkdir -p "$(dirname "$dest")"
  dot -Tsvg -o "$dest" "$(pwd)/$src"
done

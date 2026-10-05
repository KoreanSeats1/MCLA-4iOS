#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
for dependency in larecomp theft4-foundation; do
    patch="$root/patches/$dependency-ios.patch"
    if git -C "$root/$dependency" apply --reverse --check "$patch" 2>/dev/null; then
        echo "$dependency: already patched"
    else
        git -C "$root/$dependency" apply --check "$patch"
        git -C "$root/$dependency" apply "$patch"
        echo "$dependency: iOS patches applied"
    fi
done

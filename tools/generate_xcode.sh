#!/bin/sh
set -eu

workspace_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cmake_bin=${MCLA_CMAKE:-$(command -v cmake || true)}
mode=${1:-simulator}
team_id=${2:-}

if [ ! -x "$cmake_bin" ]; then
    echo "CMake is unavailable at $cmake_bin" >&2
    echo "Set MCLA_CMAKE to a CMake 3.25+ executable." >&2
    exit 1
fi

case "$mode" in
    simulator)
        preset=ios-simulator-release
        ;;
    device)
        preset=ios-device-release
        ;;
    *)
        echo "Usage: $0 [simulator|device] [APPLE_TEAM_ID]" >&2
        exit 2
        ;;
esac

if [ -n "$team_id" ]; then
    team_argument="-DMCLA_DEVELOPMENT_TEAM=$team_id"
else
    team_argument="-DMCLA_DEVELOPMENT_TEAM="
fi

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    "$cmake_bin" --preset "$preset" -S "$workspace_dir/MCLAApp" "$team_argument"

echo "Generated: $workspace_dir/out/build/$preset/MCLAApp.xcodeproj"

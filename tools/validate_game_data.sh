#!/bin/sh
set -eu

game_root=${1:-}
if [ -z "$game_root" ]; then
    echo "Usage: $0 /path/to/MCLA_Game_Files" >&2
    exit 2
fi

missing=0
for required in \
    default.xex \
    xarchive_audio.rpf \
    xarchive_audlo.rpf \
    xarchive_cache.rpf \
    xarchive_music.rpf
do
    if [ ! -f "$game_root/$required" ]; then
        echo "missing: $required" >&2
        missing=1
    fi
done

if [ "$missing" -ne 0 ]; then
    exit 1
fi

actual_hash=$(shasum -a 256 "$game_root/default.xex" | awk '{print $1}')
expected_hash=c386f4001fa569e6ad4b982f441f67412f00b3f47c166134555cd4b59854a432

if [ "$actual_hash" != "$expected_hash" ]; then
    echo "warning: default.xex differs from the recorded bring-up baseline" >&2
    echo "actual:   $actual_hash" >&2
    echo "expected: $expected_hash" >&2
    exit 3
fi

echo "MCLA Complete Edition game data is ready."
echo "default.xex SHA-256: $actual_hash"

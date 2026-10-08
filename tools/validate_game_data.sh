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
case "$actual_hash" in
    c386f4001fa569e6ad4b982f441f67412f00b3f47c166134555cd4b59854a432|6e78e00a84beee89aa23f4f3f5ed4ff7cc443e6efe356b50ec6ee8d29a8632c7)
        ;;
    *)
        echo "default.xex has not been verified for this iOS build." >&2
        echo "actual: $actual_hash" >&2
        exit 3
        ;;
esac
if [ -f "$game_root/default.xexp" ]; then
    echo "Unverified title-update patch found. Use original disc files." >&2
    exit 3
fi

echo "MCLA Complete Edition game data is ready."
echo "default.xex SHA-256: $actual_hash"

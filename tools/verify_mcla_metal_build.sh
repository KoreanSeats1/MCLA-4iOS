#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app="$root/out/build/ios-device-release/Release-iphoneos/MCLAApp.app"
test -f "$app/MCLAApp"
python3 "$root/tools/verify_mcla_metal_targets.py" "$app"
library_count=$(find "$app/MCLAMetalShaders" -name '*.metallib' | wc -l | tr -d ' ')
expected_count=$(rg -c '^\{0x' "$root/MCLAApp/generated/mcla_metal_shader_info.h")
if test "$library_count" != "$expected_count"; then
    echo "FAIL: expected $expected_count title Metal libraries, found $library_count" >&2
    exit 1
fi
symbols=$(mktemp /private/tmp/mcla-metal-symbols.XXXXXX)
trap 'rm -f "$symbols"' EXIT
nm "$app/MCLAApp" > "$symbols"
if rg 'vk(Create|Cmd|Queue)|MoltenVK|VulkanCommandProcessor|VulkanProvider' "$symbols"; then
    echo 'FAIL: legacy graphics backend linked' >&2
    exit 1
fi
rg 'MCLACreateHandwrittenMetalRenderer' "$symbols" >/dev/null
codesign --verify --strict "$app"
shasum -a256 "$app/MCLAApp"
echo "PASS: $library_count Metal libraries, hand-written backend linked, no Vulkan/MoltenVK/generic CP symbols."

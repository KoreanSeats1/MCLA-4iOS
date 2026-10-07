#!/usr/bin/env python3
"""Check startup hook placement without requiring the proprietary title binary."""
from pathlib import Path
import re
root = Path(__file__).resolve().parents[1]
for name in ('larecomp_config.toml', 'larecomp_config_xeo3.toml'):
    config = (root / 'larecomp' / name).read_text()
    hooks = [h for h in re.split(r'(?m)^\[\[midasm_hook\]\]', config)[1:]
             if re.search(r'(?m)^name\s*=\s*\"MCLA_SkipIntroVideos\"$', h)]
    assert len(hooks) == 1
    address = re.search(r'(?m)^address\s*=\s*(0x[0-9A-Fa-f]+)', hooks[0])
    jump = re.search(r'(?m)^jump_address_on_true\s*=\s*(0x[0-9A-Fa-f]+)', hooks[0])
    assert int(address[1], 16) == 0x822C2F48
    assert int(jump[1], 16) == 0x822C2F7C
source = (root / 'larecomp/src/mc_engine/hooks.cpp').read_text()
apple = source.split('#else // REXGLUE_HAS_XEO3_TARGET', 1)[1]
assert 'bool SkipIntro() { return false; }' in apple
assert 'RequestInitializedIntroSkip' in apple
assert 'PageAccess::kReadWrite' in apple
# Inspect private generated output only when available in the local checkout.
generated = root / 'MCLAApp/generated/larecomp_recomp.13.cpp'
if generated.exists():
    body = generated.read_text().split('DEFINE_REX_FUNC(rex_sub_822C2EA8)', 1)[1]
    body = body.split('DEFINE_REX_FUNC(', 1)[0]
    initialize = body.index('rex_sub_822BFD48(ctx, base);')
    context = body.index('rex_sub_821F8038(ctx, base);')
    skip = body.index('if (MCLA_SkipIntroVideos())')
    play = body.index('rex_sub_82305690(ctx, base);')
    assert initialize < context < skip < play
print('Intro video skip runs after SWF construction/context and before video play in both manifests')

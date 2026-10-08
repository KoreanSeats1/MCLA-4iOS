"""Generate tiny synthetic fixtures; contains no game data."""
from pathlib import Path
import hashlib, json, struct, sys, zipfile
root = Path(sys.argv[1]); root.mkdir(parents=True, exist_ok=True)
xex = bytearray(128); xex[:4] = b'XEX2'
for offset, value in [(20, 1), (24, 0x40006), (28, 64), (64, 0x5940C9DB), (68, 8), (72, 8), (76, 0x545407F8)]:
    struct.pack_into('>I', xex, offset, value)
required = ['default.xex', 'xarchive_audio.rpf', 'xarchive_audlo.rpf', 'xarchive_cache.rpf', 'xarchive_music.rpf']
files = {f'GAME/{n.upper()}': bytes(xex) if n == 'default.xex' else b'asset' for n in required}
files['GAME/MOVIES/INTRO.BIK'] = b'movie'
def write(name, extra=None):
    with zipfile.ZipFile(root / f'{name}.zip', 'w', zipfile.ZIP_DEFLATED) as z:
        for n, data in files.items(): z.writestr(n, data)
        for n, data in (extra or {}).items(): z.writestr(n, data)
write('good'); write('traversal', {'../escape': b'bad'})
write('collision', {'game/default.xex': bytes(xex)})
write('multiple', {f'OTHER/{n}': d for n, d in ((n.split('/', 1)[1], d) for n,d in files.items())})
write('patch', {'GAME/default.xexp': b'unverified patch'})
write('symlink')
with zipfile.ZipFile(root / 'symlink.zip', 'a') as z:
    link = zipfile.ZipInfo('GAME/link'); link.create_system = 3; link.external_attr = 0o120777 << 16
    z.writestr(link, '../outside')
b = (root / 'good.zip').read_bytes(); (root / 'truncated.zip').write_bytes(b[:64])
(root / 'manifest.json').write_text(json.dumps({'mediaId': '5940C9DB', 'baselineDefaultXexSha256': hashlib.sha256(xex).hexdigest(), 'requiredFiles': required}))

#!/usr/bin/env python3
"""Exercise the actual streaming ZIP exporter with synthetic app storage."""
import pathlib, subprocess, tempfile, zipfile
root = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='mcla-log-test-') as tmp:
    tmp = pathlib.Path(tmp)
    binary = tmp/'export'
    subprocess.run(['xcrun', 'clang++', '-std=c++17', '-fobjc-arc',
        str(root/'MCLAApp/tests/MCLALogArchiveTests.mm'),
        str(root/'MCLAApp/ios/MCLALogArchive.mm'), '-framework', 'Foundation', '-lz', '-o', str(binary)], check=True)
    home = tmp/'home'
    support = home/'Library/Application Support/MCLA'
    diagnostics = home/'Documents/Diagnostics'
    support.mkdir(parents=True)
    diagnostics.mkdir(parents=True)
    expected = {'Library/Application Support/MCLA/runtime.log': b'failure details\n',
        'Library/Application Support/MCLA/runtime.log.1': b'previous log\n',
        'Library/Application Support/MCLA/native-frame-capture/nested/frame.json': b'{}',
        'Library/Application Support/MCLA/runtime-status.txt': b'Xbox/AOT runtime setup failed.\n',
        'Documents/Diagnostics/nested/測試.csv': b'frame,ms\n' * 20000,
        'Documents/Diagnostics/empty.txt': b'',
        'Library/Application Support/MCLA/native-capture/manifest.jsonl': b'{"test":true}\n',
        'Documents/mcla-render-probe.json': b'{}'}
    for name, data in expected.items():
        path = home/name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    for name in ['Library/Application Support/MCLA/saves/private.txt',
        'Library/Application Support/MCLA/cache/private.log',
        'Documents/MCLA_Game_Files/default.xex',
        'Documents/Diagnostics/raw.rpf']:
        path = home/name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b'EXCLUDE')
    outside = tmp/'outside.txt'
    outside.write_text('EXCLUDE')
    (diagnostics/'symlink.txt').symlink_to(outside)
    archive = tmp/'logs.zip'
    subprocess.run([str(binary), str(home), str(archive)], check=True)
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
        assert set(z.namelist()) == set(expected) | {'report.txt'}, z.namelist()
        for name, data in expected.items():
            assert z.read(name) == data
    empty_home = tmp/'empty'
    empty_home.mkdir()
    subprocess.run([str(binary), str(empty_home), str(archive)], check=True)
    with zipfile.ZipFile(archive) as z:
        assert z.namelist() == ['report.txt'] and z.testzip() is None
    assert subprocess.run([str(binary), str(home), str(tmp/'missing/output.zip')]).returncode != 0
print('PASS: ZIP integrity, multi-chunk and Unicode files, empty diagnostics, game/save exclusion, symlink exclusion, output errors')

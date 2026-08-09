#!/usr/bin/env python3
"""Build the deterministic v0.x skill archive and checksum."""

from __future__ import annotations

import argparse
import hashlib
import pathlib
import zipfile


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--version', required=True)
    parser.add_argument('--output-dir', default='dist')
    args = parser.parse_args()

    root = pathlib.Path(__file__).resolve().parents[1]
    output = root / args.output_dir
    output.mkdir(parents=True, exist_ok=True)
    archive = output / f'mac-to-windows-testing-skill-{args.version}.zip'
    files = [root / 'install.sh', root / 'install.ps1', root / 'INSTALL.md', root / 'LICENSE', root / 'VERSION']
    files.extend(sorted((root / 'skills' / 'mac-to-windows-testing').rglob('*')))
    with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as bundle:
        for path in files:
            if not path.is_file():
                continue
            info = zipfile.ZipInfo(path.relative_to(root).as_posix(), date_time=(2026, 1, 1, 0, 0, 0))
            info.external_attr = (0o755 if path.suffix in {'', '.py', '.sh'} or path.name == 'mac2win-test' else 0o644) << 16
            bundle.writestr(info, path.read_bytes(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    checksum = output / 'SHA256SUMS'
    checksum.write_text(f'{digest}  {archive.name}\n', encoding='ascii')
    print(archive)
    print(checksum)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

#!/usr/bin/env python3
"""Dependency-free repository and skill integrity checks."""

from __future__ import annotations

import json
import pathlib
import re
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
SKILL = ROOT / 'skills' / 'mac-to-windows-testing'


def fail(message: str) -> None:
    print(f'ERROR: {message}', file=sys.stderr)
    raise SystemExit(1)


def main() -> int:
    required = [
        ROOT / 'README.md',
        ROOT / 'README.zh-CN.md',
        ROOT / 'INSTALL.md',
        ROOT / 'VERSION',
        ROOT / 'LICENSE',
        ROOT / 'install.sh',
        ROOT / 'install.ps1',
        SKILL / 'SKILL.md',
        SKILL / 'agents' / 'openai.yaml',
        SKILL / 'scripts' / 'mac2win_test.py',
        SKILL / 'scripts' / 'windows-runner' / 'JavaAccessBridge.psm1',
        SKILL / 'scripts' / 'windows-runner' / 'Invoke-MacToWindowsTest.ps1',
    ]
    missing = [str(path.relative_to(ROOT)) for path in required if not path.is_file()]
    if missing:
        fail('Missing required files: ' + ', '.join(missing))

    skill_text = (SKILL / 'SKILL.md').read_text(encoding='utf-8')
    if not skill_text.startswith('---\n') or '\nname: mac-to-windows-testing\n' not in skill_text:
        fail('SKILL.md frontmatter is invalid')
    for link in re.findall(r'`((?:references|assets)/[^`]+)`', skill_text):
        if not (SKILL / link).exists():
            fail(f'SKILL.md references missing file: {link}')

    for path in list((ROOT / 'schemas').glob('*.json')) + list((SKILL / 'assets').glob('*.json')):
        json.loads(path.read_text(encoding='utf-8'))

    forbidden = re.compile(
        r'(?i)(?:api[_-]?key|password|passwd|secret|bearer)\s*[=:]\s*(?!<|replace|example|true|false)[A-Za-z0-9._-]{12,}'
    )
    text_suffixes = {'.md', '.py', '.ps1', '.psm1', '.sh', '.yaml', '.yml', '.json', '.txt'}
    for path in ROOT.rglob('*'):
        if not path.is_file() or path.suffix.lower() not in text_suffixes or '.git' in path.parts:
            continue
        match = forbidden.search(path.read_text(encoding='utf-8', errors='replace'))
        if match:
            fail(f'Potential credential in {path.relative_to(ROOT)}: {match.group(0)[:24]}...')

    print('Repository validation passed.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

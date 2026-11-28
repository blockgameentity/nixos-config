#!/usr/bin/env python3
"""Reject common credentials and private operational IDs in the public source tree."""
import re
import sys
from pathlib import Path

PATTERNS = {
    'GitHub token': re.compile(r'\b(?:github_pat_[A-Za-z0-9_]+|gh[pousr]_[A-Za-z0-9_]{20,})\b'),
    'AWS access key': re.compile(r'\b(?:AKIA|ASIA)[0-9A-Z]{16}\b'),
    'private key': re.compile(r'BEGIN (?:[A-Z]+ )*PRIVATE KEY'),
    'Iroh endpoint ID': re.compile(r'(?i)(?:iroh|reseed|endpoint)[^\n]{0,50}\b[a-f0-9]{64}\b'),
    'assigned secret': re.compile(r'(?im)^\s*(?:AWS_SECRET_ACCESS_KEY|RESTIC_PASSWORD|NIX_ACCESS_TOKEN|GITHUB_TOKEN)\s*=\s*(?!<|\$|#|\s*$)\S+'),
}

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
failures = []
for path in sorted(root.rglob('*')):
    if not path.is_file() or '.git' in path.parts or path.name == 'check-public-secrets.py':
        continue
    try:
        text = path.read_text()
    except (UnicodeDecodeError, OSError):
        continue
    for label, pattern in PATTERNS.items():
        for match in pattern.finditer(text):
            failures.append(f'{path.relative_to(root)}:{text.count(chr(10), 0, match.start()) + 1}: {label}')
if failures:
    print('\n'.join(failures), file=sys.stderr)
    sys.exit('Potential public secrets found; no values were printed.')
print('Public-source secret scan passed.')

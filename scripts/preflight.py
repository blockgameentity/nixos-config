"""Read-only installation checks; never print or copy secret contents."""
import argparse
import ipaddress
import re
import stat
import subprocess
import sys
from pathlib import Path


class Checks:
    def __init__(self, secrets):
        self.secrets = secrets
        self.failures = []

    def secret(self, relative, directory=False):
        path = self.secrets / relative
        if not path.exists():
            self.failures.append(f'missing secret: {path}')
            return
        mode = stat.S_IMODE(path.stat().st_mode)
        if directory:
            if mode & 0o007:
                self.failures.append(f'world-accessible secret directory: {path} ({mode:o})')
        elif not path.is_file() or path.stat().st_size == 0:
            self.failures.append(f'empty/non-file secret: {path}')
        elif relative.startswith('cloudflare/origin'):
            # Caddy may read ONLY the certificate/key as root:caddy 0640.
            if mode & 0o077 != 0o040:
                self.failures.append(f'Caddy certificate must be root:caddy 0640: {path} ({mode:o})')
        elif mode & 0o077:
            self.failures.append(f'secret is group/world accessible: {path} ({mode:o}); chmod 0600')
        elif path.is_file() and relative.endswith('.env'):
            for number, line in enumerate(path.read_text().splitlines(), 1):
                if re.match(r'^[A-Z][A-Z0-9_]*=', line) and '\x00' in line:
                    self.failures.append(f'NUL byte in {relative}:{number}')

    def require(self, condition, message):
        if not condition:
            self.failures.append(message)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--secrets', type=Path, default=Path('/var/lib/secrets'))
    parser.add_argument('--origin', action='append', required=True,
                        help='Actual public server IPv4; repeat for each origin')
    parser.add_argument('--skip-git', action='store_true')
    args = parser.parse_args()
    checks = Checks(args.secrets)
    for value in args.origin:
        try:
            address = ipaddress.ip_address(value)
        except ValueError:
            parser.error(f'Invalid origin IPv4: {value}')
        if address.version != 4 or not address.is_global:
            parser.error(f'Use the actual public origin IPv4, not a private/reserved address: {value}')
    for relative in ['fluxer.env', 'ttml.env', 'desu-password-hash',
                        'cloudflare/origin.pem', 'cloudflare/origin-key.pem', 'ci-token', 'tailscale-auth-key']:
        checks.secret(relative)
    # Optional: cookie-based YouTube access is opt-in and only mounted into the worker.
    if (args.secrets / 'youtube-cookies.txt').exists():
        checks.secret('youtube-cookies.txt')
    checks.secret('cloudflare', directory=True)
    root = Path(__file__).resolve().parents[1]
    local = (root / 'hosts/desu/local.nix').read_text()
    hardware = (root / 'hosts/desu/hardware-configuration.nix').read_text()
    checks.require('PLACEHOLDER' not in local,
                   'Remove every PLACEHOLDER marker in local.nix (password hash, digest pins, origin IP)')
    checks.require('PLACEHOLDER' not in hardware,
                   'Replace hardware-configuration.nix with nixos-generate-config output')
    checks.require(':latest' not in local and ':migration' not in local, 'Pin application images by digest')
    for value in args.origin:
        checks.require(f'"{value}/32"' in local, f'Add actual origin {value}/32 to disposableRunners.blockedIPv4')
    checks.require('203.0.113.1/32' not in local, 'Replace documentation-only CI origin IP')
    if not args.skip_git:
        subprocess.run(['git', '-C', str(root), 'diff', '--quiet'], check=False)
        result = subprocess.run(['git', '-C', str(root), 'status', '--porcelain'], capture_output=True, text=True)
        checks.require(result.returncode == 0, 'Cannot inspect repository status')
        checks.require(not result.stdout.strip(), 'Commit/stage configuration before flake evaluation; do not commit secrets')
    if checks.failures:
        print('PREFLIGHT FAILED; no installation or secret output was performed:', file=sys.stderr)
        for failure in checks.failures:
            print(f'- {failure}', file=sys.stderr)
        raise SystemExit(1)
    print('PREFLIGHT PASSED: required files/modes and non-secret deployment settings are present.')
    print('This does NOT verify backups, hardware, certificates, tokens, or application recovery.')


if __name__ == '__main__':
    main()

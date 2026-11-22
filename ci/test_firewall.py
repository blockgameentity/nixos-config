"""Run the real generated nft policy in an isolated network namespace.

Usage: unshare --user --map-root-user --net python3 ci/test_firewall.py
Requires CAP_NET_ADMIN inside the new namespace, nftables and iproute2.
No host addresses, interfaces, or firewall rules are modified.
"""
import os
import subprocess
import sys
from pathlib import Path


def main():
    if os.environ.get('CI_FIREWALL_RULES') is None:
        raise SystemExit('Set CI_FIREWALL_RULES to a generated firewall file; see README')
    if os.getuid() != 0:
        raise SystemExit('Run in a root-mapped isolated network namespace')
    def run(command):
        return subprocess.run(command, check=True, capture_output=True, text=True)
    run(['ip', 'link', 'add', 'ci-tap1', 'type', 'dummy'])
    run(['ip', 'link', 'set', 'ci-tap1', 'up'])
    rules = Path(os.environ['CI_FIREWALL_RULES']).read_text()
    # Use a disposable table name to make accidental execution outside a test namespace less useful.
    rules = rules.replace('ci_isolation', 'ci_isolation_test')
    # Bypass the boot-time table deletion: this is a fresh isolated namespace.
    proc = subprocess.run(['nft', '-f', '-'], input=rules, text=True, capture_output=True)
    if proc.returncode:
        print(proc.stderr, file=sys.stderr)
        raise SystemExit(proc.returncode)
    result = subprocess.run(['nft', 'list', 'chain', 'inet', 'ci_isolation_test', 'forward'],
                            check=True, capture_output=True, text=True)
    policy = result.stdout
    required = [
        'iifname "ci-tap*" drop',
        'iifname "ci-tap1" ip saddr != 10.203.1.2 drop',
        '10.0.0.0/8',
        '169.254.0.0/16',
        '203.0.113.0/24',
        'tcp dport { 22, 80, 443 } accept',
        'udp dport 443 accept',
        'ct state established,related accept',
        'oifname "ci-tap*" drop',
    ]
    missing = [rule for rule in required if rule not in policy]
    if missing:
        raise AssertionError(f'Missing isolation rules: {missing}')
    forbidden = ['ip protocol tcp accept', 'iifname "ci-tap*" accept']
    for rule in forbidden:
        if rule in policy:
            raise AssertionError(f'Overbroad rule: {rule}')
    print('PASS: generated nft policy installed in isolated namespace; private/origin/input restrictions present')


if __name__ == '__main__':
    main()

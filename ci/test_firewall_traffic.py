"""Exercise guest forwarding in an isolated namespace; never touch the host firewall.

Run as root inside: unshare --user --map-root-user --net --mount
CI_FIREWALL_RULES must name the generated ci-firewall.nft file.
"""
import os
import subprocess
import time
from pathlib import Path


def run(*command, namespace=None, check=True):
    if namespace:
        command = ('ip', 'netns', 'exec', namespace, *command)
    return subprocess.run(command, check=check, capture_output=True, text=True)


def main():
    run('mount', '--make-rprivate', '/')
    run('mount', '-t', 'tmpfs', 'tmpfs', '/run')
    rules = Path(os.environ['CI_FIREWALL_RULES']).read_text().replace('ci_isolation', 'ci_isolation_test')
    rules = '\n'.join(line.replace(' drop', ' counter drop').replace(' accept', ' counter accept') if not line.lstrip().startswith('type ') else line for line in rules.splitlines())
    # Guest -> host-router -> outside HTTP server. All three networks are disposable.
    run('ip', 'link', 'add', 'ci-tap1', 'type', 'veth', 'peer', 'name', 'guest0')
    run('ip', 'link', 'add', 'out0', 'type', 'veth', 'peer', 'name', 'outside0')
    run('ip', 'netns', 'add', 'ci-guest-test')
    run('ip', 'netns', 'add', 'ci-outside-test')
    run('ip', 'link', 'set', 'guest0', 'netns', 'ci-guest-test')
    run('ip', 'link', 'set', 'outside0', 'netns', 'ci-outside-test')
    run('ip', 'addr', 'add', '10.203.1.1/30', 'dev', 'ci-tap1')
    run('ip', 'addr', 'add', '8.8.8.1/24', 'dev', 'out0')
    run('ip', 'link', 'set', 'ci-tap1', 'up')
    run('ip', 'link', 'set', 'out0', 'up')
    run('ip', 'addr', 'add', '10.203.1.2/30', 'dev', 'guest0', namespace='ci-guest-test')
    run('ip', 'link', 'set', 'lo', 'up', namespace='ci-guest-test')
    run('ip', 'link', 'set', 'guest0', 'up', namespace='ci-guest-test')
    run('ip', 'route', 'add', 'default', 'via', '10.203.1.1', namespace='ci-guest-test')
    run('ip', 'addr', 'add', '8.8.8.2/24', 'dev', 'outside0', namespace='ci-outside-test')
    run('ip', 'link', 'set', 'lo', 'up', namespace='ci-outside-test')
    run('ip', 'link', 'set', 'outside0', 'up', namespace='ci-outside-test')
    run('ip', 'route', 'add', '10.203.1.0/30', 'via', '8.8.8.1', namespace='ci-outside-test')
    run('sysctl', '-w', 'net.ipv4.ip_forward=1')
    run('iptables', '-t', 'nat', '-A', 'POSTROUTING', '-s', '10.203.0.0/16',
        '!', '-o', 'ci-tap+', '-j', 'MASQUERADE')
    result = subprocess.run(['nft', '-f', '-'], input=rules, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(result.stderr)
    servers = [subprocess.Popen(['ip', 'netns', 'exec', 'ci-outside-test', 'python3', '-m',
                                 'http.server', str(port), '--bind', '8.8.8.2'],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
               for port in (80, 25)]
    servers.append(subprocess.Popen(['python3', '-m', 'http.server', '80', '--bind', '10.203.1.1'],
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
    try:
        time.sleep(0.5)
        def guest_probe(port, address='8.8.8.2'):
            result = run('python3', '-c',
                         f'import socket; s=socket.create_connection(("{address}",{port}),1); s.close()',
                         namespace='ci-guest-test', check=False)
            return result.returncode == 0
        assert guest_probe(80), 'Allowed public HTTP was blocked'
        assert not guest_probe(25), 'Blocked SMTP was reachable'
        assert not guest_probe(80, '10.203.1.1'), 'Guest reached the host/router HTTP port'
        # 192.168.50.0/24 simulates the LAN; the outside namespace owns this route.
        run('ip', 'addr', 'add', '192.168.50.2/24', 'dev', 'outside0', namespace='ci-outside-test')
        result = run('python3', '-c',
                     'import socket; s=socket.create_connection(("192.168.50.2",80),1); s.close()',
                     namespace='ci-guest-test', check=False)
        assert result.returncode != 0, 'Guest reached a private-network address'
        result = run('python3', '-c',
                     'import socket; s=socket.socket(socket.AF_INET6); s.connect(("::1",80)); s.close()',
                     namespace='ci-guest-test', check=False)
        assert result.returncode != 0, 'Unexpected guest IPv6 connectivity'
        print('PASS: actual guest packets: HTTP allowed; SMTP, host, private LAN and IPv6 blocked')
    finally:
        for process in servers:
            process.terminate()
            process.wait()
        run('ip', 'netns', 'delete', 'ci-guest-test')
        run('ip', 'netns', 'delete', 'ci-outside-test')


if __name__ == '__main__':
    main()

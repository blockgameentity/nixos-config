"""One JIT runner per disposable VM. No GitHub management token enters the VM."""
import argparse
import json
import os
import re
import shutil
import signal
import subprocess
import tempfile
import urllib.error
import urllib.request
import uuid
from collections.abc import Callable
from pathlib import Path
from typing import Any


def read_json(path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError) as error:
        raise RuntimeError("Invalid controller configuration or recovery journal") from error


def remove_tree(path):
    try:
        shutil.rmtree(path)
    except OSError as error:
        raise RuntimeError("Cannot remove disposable VM state; refusing reuse") from error


def api_path(target):
    kind, name = target
    target = (kind, name)
    if kind == 'repository':
        if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*', name):
            raise ValueError("Expected owner/repository")
        return f'repos/{name}'
    if kind == 'organization':
        if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9-]*', name):
            raise ValueError("Invalid organization")
        return f'orgs/{name}'
    raise ValueError("Invalid runner target")


def api(token, target, method, suffix, data=None):
    path = api_path(target)
    if not re.fullmatch(r'/(generate-jitconfig|runner-groups|[0-9]+)', suffix):
        raise ValueError("Invalid GitHub API operation")
    request = urllib.request.Request(
        f"https://api.github.com/{path}/actions/runners{suffix}",
        data=None if data is None else json.dumps(data).encode(), method=method,
        headers={"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json",
                 "X-GitHub-Api-Version": "2022-11-28", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:  # noqa: S310 -- fixed HTTPS GitHub origin, validated path
            body = response.read()
            return json.loads(body) if body else None
    except urllib.error.HTTPError as error:
        # Never print response/request bodies: JIT configuration is a credential.
        if method == "DELETE" and error.code == 404:
            return None
        raise RuntimeError(f"GitHub {method} failed: HTTP {error.code}") from None


def target_of(cfg):
    repository = cfg.get('repository')
    organization = cfg.get('organization')
    if bool(repository) == bool(organization):
        raise ValueError("Configure exactly one repository or organization")
    if organization and not cfg.get('runnerGroup'):
        raise ValueError("Organization runners require a named, restricted runner group")
    return ('organization', organization) if organization else ('repository', repository)


def runner_group_id(cfg, token, api_call):
    if not cfg.get('organization'):
        return 1
    # A named group makes the repository/workflow restriction explicit. Group 1
    # is used only for repository registration, never silently for organizations.
    groups = api_call(token, target_of(cfg), 'GET', '/runner-groups')
    matches = [group['id'] for group in groups['runner_groups']
               if group['name'] == cfg['runnerGroup']]
    if len(matches) != 1:
        raise RuntimeError("Configured GitHub runner group is missing or ambiguous")
    return matches[0]


def run_once(cfg, token, state, api_call=api, popen: Callable[..., Any] = subprocess.Popen):
    target = target_of(cfg)
    pending = state / "registration.json"
    # Recover registrations left by power loss or a failed DELETE. Fail closed if cleanup fails.
    if pending.exists():
        old = read_json(pending)
        old_target = tuple(old['target']) if 'target' in old else ('repository', old['repo'])
        api_call(token, old_target, "DELETE", f"/{old['id']}")
        pending.unlink()
    for old in state.glob("job-*"):
        if old.is_dir():
            remove_tree(old)
    if shutil.disk_usage(state).free < cfg['minimumFreeGiB'] * 1024**3:
        raise RuntimeError("Admission refused: insufficient free disk space")
    work = Path(tempfile.mkdtemp(prefix="job-", dir=state))
    process = None
    try:
        subprocess.run([cfg['qemuImg'], 'create', '-q', '-f', 'qcow2', '-F', 'qcow2',
                        '-b', cfg['image'], str(work / 'disk.qcow2'), f"{cfg['diskGiB']}G"], check=True)
        registration = api_call(token, target, 'POST', '/generate-jitconfig', {
            'name': f"{cfg['name']}-{uuid.uuid4().hex[:12]}",
            'runner_group_id': runner_group_id(cfg, token, api_call),
            'labels': cfg['labels'], 'work_folder': '_work'})
        pending.write_text(json.dumps({'target': target, 'id': registration['runner']['id']}))
        # Sync the recovery journal before launching any guest.
        with pending.open('rb') as journal:
            os.fsync(journal.fileno())
        credential = work / 'jit'
        credential.write_text(registration['encoded_jit_config'])
        credential.chmod(0o600)
        cmd = [cfg['qemu'], '-enable-kvm', '-cpu', 'host', '-smp', str(cfg['cpus']),
               '-m', str(cfg['memoryMiB']), '-display', 'none', '-serial', 'none',
               '-monitor', 'none', '-no-reboot', '-nic',
               f"tap,ifname={cfg['tap']},script=no,downscript=no,model=virtio-net-pci",
               '-drive', f"file={work / 'disk.qcow2'},format=qcow2,if=virtio",
               '-fw_cfg', f"name=opt/runner,file={credential}",
               '-fw_cfg', f"name=opt/address,string={cfg['address']}"]
        process = popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            process.wait(timeout=cfg['ttlSeconds'])
        except subprocess.TimeoutExpired:
            process.terminate()
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
    finally:
        if process is not None and process.poll() is None:
            process.kill()
            process.wait()
        # Remove all writable VM state even when GitHub is unavailable.
        remove_tree(work)
        if pending.exists():
            old = read_json(pending)
            api_call(token, tuple(old['target']), 'DELETE', f"/{old['id']}")
            pending.unlink()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('config')
    args = parser.parse_args()
    os.umask(0o077)
    cfg = read_json(Path(args.config))
    token = (Path(os.environ['CREDENTIALS_DIRECTORY']) / 'github-token').read_text().strip()
    state = Path(os.environ['STATE_DIRECTORY'])
    def stop(*_):
        raise SystemExit(0)
    signal.signal(signal.SIGTERM, stop)
    run_once(cfg, token, state)


if __name__ == '__main__':
    main()

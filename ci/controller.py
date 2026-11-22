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


def validate_api_request(repo, suffix):
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*', repo):
        raise ValueError("Expected owner/repository")
    if not re.fullmatch(r'/(generate-jitconfig|[0-9]+)', suffix):
        raise ValueError("Invalid GitHub API operation")


def api(token, repo, method, suffix, data=None):
    validate_api_request(repo, suffix)
    request = urllib.request.Request(
        f"https://api.github.com/repos/{repo}/actions/runners{suffix}",
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


def run_once(cfg, token, state, api_call=api, popen: Callable[..., Any] = subprocess.Popen):
    pending = state / "registration.json"
    # Recover registrations left by power loss or a failed DELETE. Fail closed if cleanup fails.
    if pending.exists():
        old = read_json(pending)
        api_call(token, old['repo'], "DELETE", f"/{old['id']}")
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
        registration = api_call(token, cfg['repository'], 'POST', '/generate-jitconfig', {
            'name': f"{cfg['name']}-{uuid.uuid4().hex[:12]}", 'runner_group_id': 1,
            'labels': cfg['labels'], 'work_folder': '_work'})
        pending.write_text(json.dumps({'repo': cfg['repository'], 'id': registration['runner']['id']}))
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
            api_call(token, old['repo'], 'DELETE', f"/{old['id']}")
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

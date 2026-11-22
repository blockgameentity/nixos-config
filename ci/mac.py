"""Trusted-only macOS JIT runner; workspace cleanup is not a security sandbox."""
import json
import os
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path

from controller import api, read_json, remove_tree


def main():
    cfg = read_json(Path(sys.argv[1]))
    state = Path(cfg['stateDir'])
    state.mkdir(mode=0o700, parents=True, exist_ok=True)
    token = Path(cfg['tokenFile']).read_text().strip()
    pending = state / 'registration.json'
    if pending.exists():
        api(token, cfg['repository'], 'DELETE', f"/{read_json(pending)['id']}")
        pending.unlink()
    for old in state.glob('job-*'):
        if old.is_dir():
            remove_tree(old)
    work = Path(tempfile.mkdtemp(prefix='job-', dir=state))
    try:
        result = api(token, cfg['repository'], 'POST', '/generate-jitconfig', {
            'name': 'desu-mac-' + uuid.uuid4().hex[:12], 'runner_group_id': 1,
            'labels': ['self-hosted', 'macOS', 'ARM64', 'ci-mac-trusted'], 'work_folder': '_work'})
        if not isinstance(result, dict):
            raise RuntimeError('GitHub returned no registration')
        pending.write_text(json.dumps({'id': result['runner']['id']}))
        environment = os.environ | {'RUNNER_ROOT': str(work), 'HOME': str(work)}
        subprocess.run([cfg['runner'], 'run', '--jitconfig', result['encoded_jit_config']],
                       cwd=work, env=environment, check=False, timeout=cfg['ttlSeconds'])
    finally:
        remove_tree(work)
        if pending.exists():
            api(token, cfg['repository'], 'DELETE', f"/{read_json(pending)['id']}")
            pending.unlink()


if __name__ == '__main__':
    os.umask(0o077)
    main()

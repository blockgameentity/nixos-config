import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

import controller


class LifecycleTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.state = Path(self.tmp.name)
        self.cfg = {'repository': 'owner/repo', 'name': 'test', 'labels': ['ci-public-x64'],
                    'minimumFreeGiB': 0, 'qemuImg': 'qemu-img', 'qemu': 'qemu', 'image': '/image',
                    'diskGiB': 80, 'cpus': 4, 'memoryMiB': 1024, 'tap': 'ci-tap1',
                    'address': '10.203.1', 'ttlSeconds': 60}
        self.calls = []
        def api(token, repo, method, suffix, data=None):
            self.calls.append((repo, method, suffix, data))
            if method == 'POST':
                return {'runner': {'id': 42}, 'encoded_jit_config': 'SHORT-LIVED-JIT'}
        self.api = api
        self.process = Mock()
        self.process.poll.return_value = 0
        self.process.wait.return_value = 0
        self.popen = Mock(return_value=self.process)

    def run_job(self):
        with patch('controller.subprocess.run'):
            controller.run_once(self.cfg, 'HOST-TOKEN', self.state, self.api, self.popen)

    def test_success_deletes_disk_and_registration(self):
        self.run_job()
        self.assertEqual(list(self.state.iterdir()), [])
        self.assertEqual(self.calls[-1][1:3], ('DELETE', '/42'))
        command = self.popen.call_args.args[0]
        self.assertNotIn('HOST-TOKEN', ' '.join(command))
        self.assertNotIn('SHORT-LIVED-JIT', ' '.join(command))
        self.assertIn('-enable-kvm', command)
        self.assertFalse(any('virtfs' in x or 'hostfwd' in x for x in command))

    def test_timeout_terminates_guest(self):
        self.process.wait.side_effect = [subprocess.TimeoutExpired('qemu', 60), 0]
        self.run_job()
        self.process.terminate.assert_called_once()
        self.assertEqual(list(self.state.iterdir()), [])

    def test_stubborn_guest_is_killed(self):
        self.process.wait.side_effect = [subprocess.TimeoutExpired('qemu', 60),
                                         subprocess.TimeoutExpired('qemu', 15), 0]
        self.run_job()
        self.process.kill.assert_called_once()

    def test_launch_failure_still_cleans_up(self):
        self.popen.side_effect = OSError('KVM unavailable')
        with self.assertRaises(OSError):
            self.run_job()
        self.assertEqual(list(self.state.iterdir()), [])
        self.assertEqual(self.calls[-1][1:3], ('DELETE', '/42'))

    def test_recovery_deletes_previous_registration_and_disk(self):
        (self.state / 'registration.json').write_text(json.dumps({'repo': 'old/repo', 'id': 99}))
        (self.state / 'job-orphan').mkdir()
        self.run_job()
        self.assertEqual(self.calls[0][:3], ('old/repo', 'DELETE', '/99'))
        self.assertEqual(list(self.state.iterdir()), [])

    def test_failed_deregistration_retains_journal_not_disk(self):
        original = self.api
        def api(*args):
            if args[2] == 'DELETE':
                raise RuntimeError('offline')
            return original(*args)
        self.api = api
        with self.assertRaises(RuntimeError):
            self.run_job()
        self.assertTrue((self.state / 'registration.json').exists())
        self.assertEqual(list(self.state.glob('job-*')), [])

    def test_disk_admission_denies_before_registration(self):
        self.cfg['minimumFreeGiB'] = 10**12
        with self.assertRaises(RuntimeError):
            self.run_job()
        self.assertEqual(self.calls, [])

    def test_api_rejects_untrusted_paths(self):
        with self.assertRaises(ValueError):
            controller.api('secret', '../bad', 'POST', '/generate-jitconfig')
        with self.assertRaises(ValueError):
            controller.api('secret', 'owner/repo', 'GET', '/../../bad')


if __name__ == '__main__':
    unittest.main()

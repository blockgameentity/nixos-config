import os
import tempfile
import unittest
from pathlib import Path

from preflight import Checks


class PreflightTests(unittest.TestCase):
    @unittest.skipUnless(hasattr(os, 'geteuid') and os.geteuid() == 0, 'needs chown')
    def test_cookie_file_must_be_worker_owned(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'youtube-cookies.txt'
            p.write_text('cookie')
            os.chown(p, 10001, 10001)
            p.chmod(0o400)
            c = Checks(Path(d))
            c.secret(p.name)
            self.assertEqual(c.failures, [])
            p.chmod(0o600)
            os.chown(p, 0, 0)
            c.secret(p.name)
            self.assertEqual(len(c.failures), 1)

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.checks = Checks(self.root)

    def secret(self, name, mode=0o600, contents='value'):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents)
        path.chmod(mode)

    def test_missing_secret_fails(self):
        self.checks.secret('fluxer.env')
        self.assertIn('missing', self.checks.failures[0])

    def test_caddy_group_read_is_permitted_only_for_certificates(self):
        self.secret('cloudflare/origin-key.pem', 0o640)
        self.secret('ci-token', 0o640)
        self.checks.secret('cloudflare/origin-key.pem')
        self.checks.secret('ci-token')
        self.assertEqual(len(self.checks.failures), 1)
        self.assertIn('ci-token', self.checks.failures[0])

    def test_caddy_world_read_fails(self):
        self.secret('cloudflare/origin.pem', 0o644)
        self.checks.secret('cloudflare/origin.pem')
        self.assertEqual(len(self.checks.failures), 1)

    def test_empty_secret_fails(self):
        self.secret('ci-token', contents='')
        self.checks.secret('ci-token')
        self.assertIn('empty', self.checks.failures[0])

    def test_normal_secret_passes(self):
        self.secret('fluxer.env', contents='KEY=value\n')
        self.checks.secret('fluxer.env')
        self.assertEqual(self.checks.failures, [])


if __name__ == '__main__':
    unittest.main()

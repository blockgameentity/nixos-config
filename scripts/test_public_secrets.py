import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCANNER = Path(__file__).with_name('check-public-secrets.py')


class PublicSecretScanTests(unittest.TestCase):
    def scan(self, text):
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, 'example.txt').write_text(text)
            return subprocess.run([sys.executable, SCANNER, directory], capture_output=True, text=True)

    def test_clean_documentation(self):
        self.assertEqual(self.scan('tokenFile = "/var/lib/secrets/token";\n').returncode, 0)

    def test_rejects_endpoint_id_without_printing_it(self):
        endpoint = 'a' * 64
        result = self.scan(f'old reseed endpoint ID: {endpoint}\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(endpoint, result.stderr)

    def test_rejects_token_without_printing_it(self):
        result = self.scan('AWS_SECRET_ACCESS_KEY=not-a-real-example-secret\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('not-a-real-example-secret', result.stderr)


if __name__ == '__main__':
    unittest.main()

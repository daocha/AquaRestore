import hashlib
import importlib.util
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("feature_build", Path(__file__).resolve().parents[1] / "prepare-ios-features.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class FeatureBuildTests(unittest.TestCase):
    def generate(self, code):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            if code is not None:
                (root / ".env").write_text('export AQUARESTORE_BATCH_UNLOCK_CODE="' + code + '"\n')
            output = root / "app" / "BatchGate.plist"
            with patch.dict(os.environ, {}, clear=True):
                module.generate(root, output)
            return plistlib.loads(output.read_bytes()), output.read_bytes()

    def test_missing_setting_enables_features(self):
        values, _ = self.generate(None)
        self.assertEqual(values["verifier"], "")

    def test_only_salted_verifier_is_packaged(self):
        code = "sample-測試-5678"
        first, raw = self.generate(code)
        second, _ = self.generate(code)
        self.assertNotIn(code.encode(), raw)
        self.assertNotEqual(first["salt"], second["salt"])
        expected = hashlib.pbkdf2_hmac("sha256", code.encode(), bytes.fromhex(first["salt"]), 120000).hex()
        self.assertEqual(expected, first["verifier"])
        self.assertNotEqual(first["verifier"], hashlib.pbkdf2_hmac("sha256", b"wrong", bytes.fromhex(first["salt"]), 120000).hex())

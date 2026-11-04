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
    def generate(self, photo=None, video=None, environment=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            settings = {"PHOTO": photo, "VIDEO": video}
            (root / ".env").write_text("".join(
                f'export AQUARESTORE_BATCH_{kind}_UNLOCK_CODE="{code}"\n'
                for kind, code in settings.items() if code is not None))
            output = root / "app" / "BatchGate.plist"
            with patch.dict(os.environ, environment or {}, clear=True):
                module.generate(root, output)
            return plistlib.loads(output.read_bytes()), output.read_bytes()

    def test_legacy_unlock_environment_is_ignored_and_not_packaged(self):
        values, raw = self.generate(photo="old-photo-secret", video="old-video-secret", environment={
            "CONFIGURATION": "Release", "AQUARESTORE_BATCH_PHOTO_UNLOCK_CODE": "exported-secret"})
        self.assertEqual({"referralBackendURL": ""}, values)
        for secret in (b"old-photo-secret", b"old-video-secret", b"exported-secret"):
            self.assertNotIn(secret, raw)

    def test_backend_configuration_is_the_only_gate(self):
        values, _ = self.generate()
        self.assertEqual({"referralBackendURL": ""}, values)
        values, _ = self.generate(environment={"CONFIGURATION": "Debug",
            "AQUARESTORE_REFERRAL_BACKEND_URL": "https://example.org/referrals/"})
        self.assertEqual("https://example.org/referrals", values["referralBackendURL"])
        self.assertFalse(any("Verifier" in key or "Salt" in key for key in values))

    def test_root_dotenv_url_and_exported_empty_override(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / ".env").write_text('AQUARESTORE_REFERRAL_BACKEND_URL=https://example.org\n')
            output = root / "BatchGate.plist"
            with patch.dict(os.environ, {}, clear=True):
                module.generate(root, output)
            self.assertEqual("https://example.org", plistlib.loads(output.read_bytes())["referralBackendURL"])
            with patch.dict(os.environ, {"AQUARESTORE_REFERRAL_BACKEND_URL": ""}, clear=True):
                module.generate(root, output)
            self.assertEqual("", plistlib.loads(output.read_bytes())["referralBackendURL"])

    def test_rejects_invalid_backend_urls(self):
        for backend in ("ftp://example.org", "https://a:b@example.org", "https://example.org?token=secret", "https://@example.org", "https://example.org?", "https://example.org#"):
            with self.subTest(backend=backend), self.assertRaises(ValueError):
                self.generate(environment={"AQUARESTORE_REFERRAL_BACKEND_URL": backend})

    def test_debug_referral_secret_is_never_packaged_in_release(self):
        environment = {"AQUARESTORE_REFERRAL_DEBUG_TOKEN": "test_" + "x" * 40, "CONFIGURATION": "Debug"}
        values, _ = self.generate(environment=environment)
        self.assertEqual(environment["AQUARESTORE_REFERRAL_DEBUG_TOKEN"], values["referralDebugToken"])
        environment["CONFIGURATION"] = "Release"
        values, raw = self.generate(environment=environment)
        self.assertNotIn("referralDebugToken", values)
        self.assertNotIn(environment["AQUARESTORE_REFERRAL_DEBUG_TOKEN"].encode(), raw)

    def test_platform_verification_can_be_enabled_explicitly_in_debug_only(self):
        values, _ = self.generate(environment={"CONFIGURATION": "Debug", "PRODUCT_BUNDLE_IDENTIFIER": "com.aquarestore.app.debug"})
        self.assertEqual("token", values["referralDebugVerification"])
        values, _ = self.generate(environment={"CONFIGURATION": "Debug", "PRODUCT_BUNDLE_IDENTIFIER": "com.aquarestore.app.debug",
                                               "AQUARESTORE_REFERRAL_DEBUG_VERIFICATION": "platform"})
        self.assertEqual("platform", values["referralDebugVerification"])
        values, _ = self.generate(environment={"CONFIGURATION": "Release", "AQUARESTORE_REFERRAL_DEBUG_VERIFICATION": "token"})
        self.assertNotIn("referralDebugVerification", values)
        with self.assertRaises(ValueError):
            self.generate(environment={"CONFIGURATION": "Debug", "AQUARESTORE_REFERRAL_DEBUG_VERIFICATION": "invalid"})

    def test_release_referral_http_is_rejected_and_debug_scheme_is_normalized(self):
        with self.assertRaises(ValueError):
            self.generate(environment={"CONFIGURATION": "Release", "AQUARESTORE_REFERRAL_BACKEND_URL": "http://example.org"})
        values, _ = self.generate(environment={"CONFIGURATION": "Debug", "AQUARESTORE_REFERRAL_BACKEND_URL": "HTTP://127.0.0.1:8080"})
        self.assertEqual("http://127.0.0.1:8080", values["referralBackendURL"])
        for port in ("bad", "0", "65536"):
            with self.subTest(port=port), self.assertRaises(ValueError):
                self.generate(environment={"AQUARESTORE_REFERRAL_BACKEND_URL": "https://example.org:" + port})

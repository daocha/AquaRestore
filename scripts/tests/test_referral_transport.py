import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("transport", Path(__file__).resolve().parents[1] / "prepare-ios-referral-transport.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ReferralTransportTests(unittest.TestCase):
    def test_http_is_allowed_only_in_debug_with_campaign_enabled(self):
        with tempfile.TemporaryDirectory() as directory:
            info, gate = Path(directory) / "Info.plist", Path(directory) / "BatchGate.plist"
            for debug, backend, expected in ((True, "http://127.0.0.1:8080", True), (False, "http://example.org", False),
                                             (True, "", False), (True, "https://example.org", False)):
                info.write_bytes(plistlib.dumps({"CFBundleIdentifier": "test.app"}))
                gate.write_bytes(plistlib.dumps({"referralBackendURL": backend}))
                module.configure(info, gate, debug)
                actual = plistlib.loads(info.read_bytes())
                self.assertEqual(expected, actual.get("NSAppTransportSecurity", {}).get("NSAllowsArbitraryLoads", False))
                self.assertEqual(expected, "NSLocalNetworkUsageDescription" in actual)
                self.assertEqual("test.app", actual["CFBundleIdentifier"])

    def test_preserves_existing_transport_settings_and_restores_them_after_http_testing(self):
        original = {"CFBundleIdentifier": "test.app", "NSAppTransportSecurity": {
            "NSAllowsArbitraryLoads": False, "NSExceptionDomains": {"example.org": {"NSIncludesSubdomains": True}}},
            "NSLocalNetworkUsageDescription": "Existing local network explanation"}
        with tempfile.TemporaryDirectory() as directory:
            info, gate = Path(directory) / "Info.plist", Path(directory) / "BatchGate.plist"
            info.write_bytes(plistlib.dumps(original))
            gate.write_bytes(plistlib.dumps({"referralBackendURL": ""}))
            module.configure(info, gate, False)
            self.assertEqual(original, plistlib.loads(info.read_bytes()))
            gate.write_bytes(plistlib.dumps({"referralBackendURL": "http://127.0.0.1:8080"}))
            module.configure(info, gate, True)
            module.configure(info, gate, True)
            testing = plistlib.loads(info.read_bytes())
            self.assertTrue(testing["NSAppTransportSecurity"]["NSAllowsArbitraryLoads"])
            self.assertEqual(original["NSAppTransportSecurity"]["NSExceptionDomains"], testing["NSAppTransportSecurity"]["NSExceptionDomains"])
            self.assertEqual(original["NSLocalNetworkUsageDescription"], testing["NSLocalNetworkUsageDescription"])
            gate.write_bytes(plistlib.dumps({"referralBackendURL": ""}))
            module.configure(info, gate, True)
            self.assertEqual(original, plistlib.loads(info.read_bytes()))

    def test_removes_old_script_exception_when_campaign_is_disabled(self):
        with tempfile.TemporaryDirectory() as directory:
            info, gate = Path(directory) / "Info.plist", Path(directory) / "BatchGate.plist"
            info.write_bytes(plistlib.dumps({"NSAppTransportSecurity": {"NSAllowsArbitraryLoads": True},
                                            "NSLocalNetworkUsageDescription": module.DESCRIPTION}))
            gate.write_bytes(plistlib.dumps({"referralBackendURL": ""}))
            module.configure(info, gate, True)
            self.assertEqual({}, plistlib.loads(info.read_bytes()))

#!/usr/bin/env python3
"""Apply a debug-only HTTP exception to the processed app plist, before signing."""
import os
from pathlib import Path
import plistlib

MARKER = "AquaRestoreReferralTransportOriginal"
DESCRIPTION = "Connect to your configured referral server on the local network."
KEYS = ("NSAppTransportSecurity", "NSLocalNetworkUsageDescription")


def configure(info_path, gate_path, debug):
    info = plistlib.loads(info_path.read_bytes())
    gate = plistlib.loads(gate_path.read_bytes())
    original = info.pop(MARKER, None)
    if original is not None:
        for key in KEYS:
            if key in original:
                info[key] = original[key]
            else:
                info.pop(key, None)
    elif (info.get("NSAppTransportSecurity") == {"NSAllowsArbitraryLoads": True}
          and info.get("NSLocalNetworkUsageDescription") == DESCRIPTION):
        # Clean up a processed plist left by the earlier version of this script.
        for key in KEYS:
            info.pop(key, None)
    if debug and gate.get("referralBackendURL", "").startswith("http://"):
        info[MARKER] = {key: info[key] for key in KEYS if key in info}
        transport = dict(info.get("NSAppTransportSecurity", {}))
        transport["NSAllowsArbitraryLoads"] = True
        info["NSAppTransportSecurity"] = transport
        info.setdefault("NSLocalNetworkUsageDescription", DESCRIPTION)
    info_path.write_bytes(plistlib.dumps(info))


if __name__ == "__main__":
    build = Path(os.environ["TARGET_BUILD_DIR"])
    configure(build / os.environ["INFOPLIST_PATH"],
              build / os.environ["UNLOCALIZED_RESOURCES_FOLDER_PATH"] / "BatchGate.plist",
              os.environ.get("CONFIGURATION", "").lower() == "debug")

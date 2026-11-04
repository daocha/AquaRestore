#!/usr/bin/env python3
import hashlib
import os
from pathlib import Path
import plistlib


def generate(root, destination):
    values = {}
    env = root / ".env"
    if env.exists():
        for line in env.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.removeprefix("export ").split("=", 1)
                values[key.strip()] = value.strip().strip("\"'")
    config = {}
    for feature in ("photo", "video"):
        name = "AQUARESTORE_BATCH_" + feature.upper() + "_UNLOCK_CODE"
        code = os.environ.get(name, values.get(name, ""))
        if os.environ.get("CONFIGURATION", "").lower() == "debug":
            code = os.environ["PRODUCT_BUNDLE_IDENTIFIER"]
        salt = os.urandom(16)
        verifier = hashlib.pbkdf2_hmac("sha256", code.encode(), salt, 120000).hex() if code else ""
        config[feature + "Salt"] = salt.hex()
        config[feature + "Verifier"] = verifier
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(plistlib.dumps(config))



if __name__ == "__main__":
    generate(Path(__file__).resolve().parent.parent,
             Path(os.environ["TARGET_BUILD_DIR"]) / os.environ["UNLOCALIZED_RESOURCES_FOLDER_PATH"] / "BatchGate.plist")

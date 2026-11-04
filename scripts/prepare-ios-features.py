#!/usr/bin/env python3
import os
from pathlib import Path
import plistlib
from urllib.parse import urlsplit, urlunsplit


def generate(root, destination):
    values = {}
    env = root / ".env"
    if env.exists():
        for line in env.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.removeprefix("export ").split("=", 1)
                values[key.strip()] = value.strip().strip("\"'")
    def setting(name):
        return os.environ.get(name, values.get(name, ""))
    backend = setting("AQUARESTORE_REFERRAL_BACKEND_URL").strip().rstrip("/")
    if backend:
        url = urlsplit(backend)
        if url.scheme not in ("https", "http") or not url.hostname or "?" in backend or "#" in backend or url.username is not None or url.password is not None:
            raise ValueError("Referral backend must be an HTTP(S) base URL without credentials, query or fragment")
        if url.port is not None and not 1 <= url.port <= 65535:
            raise ValueError("Referral backend port must be between 1 and 65535")
        if os.environ.get("CONFIGURATION", "").lower() == "release" and url.scheme != "https":
            raise ValueError("Release referral campaigns require an HTTPS backend URL")
        backend = urlunsplit((url.scheme, url.netloc, url.path, "", ""))
    config = {"referralBackendURL": backend}
    if os.environ.get("CONFIGURATION", "").lower() == "debug":
        verification = setting("AQUARESTORE_REFERRAL_DEBUG_VERIFICATION").strip() or "token"
        if verification not in ("token", "platform"):
            raise ValueError("Debug referral verification must be token or platform")
        config["referralDebugVerification"] = verification
        token = setting("AQUARESTORE_REFERRAL_DEBUG_TOKEN")
        if token and (not token.isascii() or any(c not in "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-" for c in token)):
            raise ValueError("Debug referral token must be base64url")
        config["referralDebugToken"] = token
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(plistlib.dumps(config))



if __name__ == "__main__":
    generate(Path(__file__).resolve().parent.parent,
             Path(os.environ["TARGET_BUILD_DIR"]) / os.environ["UNLOCALIZED_RESOURCES_FOLDER_PATH"] / "BatchGate.plist")

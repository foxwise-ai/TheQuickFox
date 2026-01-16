#!/usr/bin/env python3
import json
import sys
import os
from datetime import datetime
from urllib.request import Request, urlopen
from urllib.error import HTTPError


def main():
    version = os.environ["VERSION"]
    channel = "beta" if "beta" in version else "stable"
    release_notes = os.environ.get("RELEASE_NOTES", "")
    github_repo = os.environ.get("GITHUB_REPOSITORY", "foxwise-ai/TheQuickFox")
    signature = os.environ["SPARKLE_SIGNATURE"]
    file_size = int(os.environ["FILE_SIZE"])
    api_token = os.environ["INTERNAL_API_TOKEN"]

    payload = {
        "version": version,
        "build_number": version,
        "channel": channel,
        "release_notes": release_notes,
        "download_url": f"https://github.com/{github_repo}/releases/download/v{version}/TheQuickFox-{version}.zip",
        "signature": signature,
        "file_size": file_size,
        "minimum_os_version": "13.0",
        "is_critical": False,
        "published_at": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    }

    data = json.dumps(payload).encode("utf-8")
    req = Request(
        "https://api.thequickfox.ai/api/v1/internal/releases",
        data=data,
        headers={
            "Authorization": f"Bearer {api_token}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with urlopen(req) as response:
            status = response.status
            body = response.read().decode("utf-8")
            print(f"HTTP Status: {status}")
            print(f"Response: {body}")

            if status != 201:
                print("❌ Failed to create release record")
                sys.exit(1)

            print("✅ Release record created successfully")
    except HTTPError as e:
        print(f"HTTP Status: {e.code}")
        print(f"Response: {e.read().decode('utf-8')}")
        print("❌ Failed to create release record")
        sys.exit(1)


if __name__ == "__main__":
    main()

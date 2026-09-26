#!/usr/bin/env python3
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

"""Signs a HAP with the public OpenHarmony test keys of the SDK.

OpenHarmony devices install HAPs signed this way. The provisioning profile is a release profile for
the bundle of the HAP, so it works on any such device without listing device ids.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import zipfile
from pathlib import Path

# The password of the public test keystore `OpenHarmony.p12` in the SDK.
KEYSTORE_PASSWORD = "123456"
PEM_CERTIFICATE = re.compile(r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", re.S)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("unsigned", type=Path, help="the HAP to sign")
    parser.add_argument("signed", type=Path, help="where to write the signed HAP")
    parser.add_argument(
        "--sdk",
        type=Path,
        help="the OpenHarmony SDK, by default $OHOS_BASE_SDK_HOME/<api>",
    )
    parser.add_argument("--api", default="21", help="the API level of the SDK to use (default: 21)")
    args = parser.parse_args()

    sdk = args.sdk
    if sdk is None:
        if "OHOS_BASE_SDK_HOME" not in os.environ:
            parser.error("pass --sdk or set OHOS_BASE_SDK_HOME")
        sdk = Path(os.environ["OHOS_BASE_SDK_HOME"]) / args.api
    lib = sdk / "toolchains" / "lib"
    keystore = lib / "OpenHarmony.p12"

    with zipfile.ZipFile(args.unsigned) as hap:
        bundle_name = json.loads(hap.read("module.json"))["app"]["bundleName"]

    profile = json.loads((lib / "UnsgnedReleasedProfileTemplate.json").read_text())
    profile["bundle-info"]["bundle-name"] = bundle_name
    now = int(time.time())
    profile["validity"] = {"not-before": now - 24 * 3600, "not-after": now + 10 * 365 * 24 * 3600}

    # The chain of the release key: the root and intermediate CA, which also issued the profile
    # signing certificate, and the release certificate the profile names.
    root_ca, app_ca = PEM_CERTIFICATE.findall((lib / "OpenHarmonyProfileRelease.pem").read_text())[:2]
    release_certificate = profile["bundle-info"]["distribution-certificate"].strip()

    with tempfile.TemporaryDirectory() as work:
        work = Path(work)
        (work / "profile.json").write_text(json.dumps(profile, indent=2))
        (work / "app.pem").write_text("\n".join([root_ca, app_ca, release_certificate]) + "\n")
        sign_tool = ["java", "-jar", str(lib / "hap-sign-tool.jar")]
        common = [
            "-signAlg", "SHA256withECDSA",
            "-mode", "localSign",
            "-keystoreFile", str(keystore),
            "-keystorePwd", KEYSTORE_PASSWORD,
            "-keyPwd", KEYSTORE_PASSWORD,
        ]
        subprocess.run(
            sign_tool + ["sign-profile"] + common + [
                "-keyAlias", "openharmony application profile release",
                "-profileCertFile", str(lib / "OpenHarmonyProfileRelease.pem"),
                "-inFile", str(work / "profile.json"),
                "-outFile", str(work / "profile.p7b"),
            ],
            check=True,
        )
        subprocess.run(
            sign_tool + ["sign-app"] + common + [
                "-keyAlias", "openharmony application release",
                "-appCertFile", str(work / "app.pem"),
                "-profileFile", str(work / "profile.p7b"),
                "-inFile", str(args.unsigned),
                "-outFile", str(args.signed),
            ],
            check=True,
        )
    print(f"Signed {bundle_name} as {args.signed}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

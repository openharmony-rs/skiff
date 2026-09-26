#!/usr/bin/env python3
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

"""Regenerates the page that `servo:license` shows, with cargo-about.

The configuration is `tools/about/servo.toml`, for Servo's dependencies, with `overlay.toml` on
top. The template `about.hbs` includes partials, the static ones in `tools/about/` and these
generated ones:

- `rust-std`: the notices of the Rust standard library, from the toolchain.
- `spidermonkey`: the notices of the code in SpiderMonkey that is not under the MPL 2.0. If the
  `mozjs_sys` crate has them in `licenses/`, they are added to the configuration instead, otherwise
  they come from `tools/about/mozjs_sys-<version>/`, which mozjs' `etc/licenses.py` generated.

Run it after changing dependencies. Needs `cargo install cargo-about --locked --features cli`.
"""

import argparse
import hashlib
import html
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parent.parent
ABOUT_DIR = REPOSITORY / "tools" / "about"
OUTPUT = REPOSITORY / "crates" / "core" / "resources" / "license.html"


def mozjs_sys(manifest_path):
    metadata = json.loads(subprocess.check_output(
        ["cargo", "metadata", "--format-version", "1", "--manifest-path", str(manifest_path)],
        cwd=REPOSITORY,
    ))
    packages = [package for package in metadata["packages"] if package["name"] == "mozjs_sys"]
    if len(packages) != 1:
        raise Exception(f"Expected one mozjs_sys, found {len(packages)}")
    return packages[0]


def mozjs_sys_clarification(package, notices):
    """A clarification of cargo-about that lists the notice files of mozjs_sys."""
    lines = [f'[mozjs_sys.clarify]\nlicense = "{package["license"]}"\n']
    for notice in notices:
        checksum = hashlib.sha256(notice.read_bytes()).hexdigest()
        lines.append(f'[[mozjs_sys.clarify.files]]\npath = "licenses/{notice.name}"\n'
                     f'license = "{notice.stem}"\nchecksum = "{checksum}"\n')
    return "\n".join(lines)


def spidermonkey_partials(notices, version):
    sections = "\n".join(
        f'<h3 id="spidermonkey-{notice.stem}">{notice.stem}</h3>\n'
        f'<pre class="license-text">{html.escape(notice.read_text(), quote=False)}</pre>'
        for notice in notices
    )
    section = (f'<section id="spidermonkey">\n<h2>SpiderMonkey</h2>\n<p>The parts of SpiderMonkey, as '
               f'built by mozjs_sys {version}, under each license:</p>\n{sections}\n</section>\n')
    overview = '<li><a href="#spidermonkey">SpiderMonkey</a></li>\n'
    return escape_handlebars(section), overview


def rust_std_partial():
    sysroot = subprocess.check_output(["rustc", "--print", "sysroot"], cwd=REPOSITORY, text=True)
    page = (Path(sysroot.strip()) / "share" / "doc" / "rust" / "COPYRIGHT-library.html").read_text()
    body = re.search(r"<body[^>]*>(.*)</body>", page, re.DOTALL).group(1)
    return escape_handlebars(
        '<section id="rust-std">\n<details>\n<summary><h2>The Rust Standard Library</h2></summary>\n'
        f"{body}\n</details>\n</section>\n"
    )


def escape_handlebars(text):
    return text.replace("{{", "\\{{")


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--manifest-path", type=Path, default=REPOSITORY / "Cargo.toml")
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()

    config = (ABOUT_DIR / "overlay.toml").read_text() + "\n" + (ABOUT_DIR / "servo.toml").read_text()
    package = mozjs_sys(args.manifest_path)
    crate_notices = sorted((Path(package["manifest_path"]).parent / "licenses").glob("*.txt"))
    if crate_notices:
        config += "\n" + mozjs_sys_clarification(package, crate_notices)
        spidermonkey, overview = "", ""
    else:
        vendored = ABOUT_DIR / f"mozjs_sys-{package['version']}"
        notices = sorted(vendored.glob("*.txt"))
        if not notices:
            print(f"mozjs_sys {package['version']} has no licenses/, and {vendored} is missing. "
                  "Generate it with etc/licenses.py of mozjs.", file=sys.stderr)
            return 1
        # The rest comes from the partial, but a clarification needs a file.
        mpl = Path(package["manifest_path"]).parent / "mozjs" / "nsprpub" / "LICENSE"
        config += (f'\n[mozjs_sys.clarify]\nlicense = "MPL-2.0"\n\n[[mozjs_sys.clarify.files]]\n'
                   f'path = "mozjs/nsprpub/LICENSE"\nlicense = "MPL-2.0"\n'
                   f'checksum = "{hashlib.sha256(mpl.read_bytes()).hexdigest()}"\n')
        spidermonkey, overview = spidermonkey_partials(notices, package["version"])

    with tempfile.TemporaryDirectory() as directory:
        templates = Path(directory)
        for template in ABOUT_DIR.glob("*.hbs"):
            (templates / template.name).write_text(template.read_text())
        (templates / "spidermonkey.hbs").write_text(spidermonkey)
        (templates / "spidermonkey-overview.hbs").write_text(overview)
        (templates / "rust-std.hbs").write_text(rust_std_partial())
        (templates / "about.toml").write_text(config)
        subprocess.check_call(
            ["cargo", "about", "generate", "--fail", "--config", str(templates / "about.toml"),
             "--manifest-path", str(args.manifest_path), "--name", "about", "--output-file",
             str(args.output), str(templates)],
            cwd=REPOSITORY,
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())

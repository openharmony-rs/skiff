/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

use std::env;
use std::fs::{self, File};
use std::io::Write;
use std::path::PathBuf;

use flate2::Compression;
use flate2::write::GzEncoder;

/// Compresses the license page that `servo:license` shows, to a twentieth of its size.
fn main() {
    let source = "resources/license.html";
    println!("cargo::rerun-if-changed={source}");
    let html =
        fs::read(source).expect("resources/license.html is missing, run tools/update-licenses.sh");
    let path = PathBuf::from(env::var_os("OUT_DIR").unwrap()).join("license.html.gz");
    let mut encoder = GzEncoder::new(File::create(path).unwrap(), Compression::best());
    encoder.write_all(&html).unwrap();
    encoder.finish().unwrap();
}

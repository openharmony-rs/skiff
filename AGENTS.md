# Skiff

See `README.md` for the layout, the build and the API.

- `servo` is a submodule that points at a published commit of servo-ohos' `ohos-main`. Land Servo
  changes there (or upstream) first, and keep them to what the webview needs. When moving the
  submodule, sync what `Cargo.toml`, `.cargo/config.toml`, `rust-toolchain.toml`, `rustfmt.toml` and
  `Cargo.lock` copy from servo, and recheck the preference lists and the license page.
- Format with `just fmt` and lint with `just clippy`; `just --list` shows the other recipes.
- Run the on-device tests with `just [device=<serial>] test` (see `README.md`) after changes to the
  crates or the HAR, and add tests for new behavior to `entry/src/ohosTest`. Unlock the screen
  first: a locked screen makes every test time out, since the test page can't come to the
  foreground.
- After changing dependencies, run `just licenses` (needs
  `cargo install cargo-about --locked --features cli`) and commit the regenerated license page. If a
  sys crate now builds other C or C++ code, add a `clarify` entry to `tools/about/servo.toml`. A new
  mozjs_sys version needs its notices in `tools/about/mozjs_sys-<version>/` until mozjs ships them.
- When updating Servo, recheck the lists in `crates/core/src/preferences.rs`: which preferences need
  a restart or are unused comes from where Servo reads them, and the experimental ones are a copy of
  servoshell's `EXPERIMENTAL_PREFS`.
- Test on a device: install the demo app with `just install` and verify rendering with screenshots
  (`snapshot_display`), not only logs. The demo app's `eval` launch parameter runs a script after
  each load and logs the result. Debug logs need `hilog -b D` on the device (restore with
  `hilog -b I`), and `uitest uiInput text` types with key events, not the soft keyboard.

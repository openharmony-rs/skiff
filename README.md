# Skiff

An alternative to ArkWeb's `Web` component, backed by the [Servo](https://servo.org) web engine, in
the spirit of GeckoView on Android: an app adds the `@openharmony-rs/skiff` HAR and uses the
`SkiffView` component instead of `Web`. No system modification is needed, so it works wherever the
app can be installed, from OpenHarmony 7.0 (API 26) on.

```ts
import { SkiffView, SkiffController } from '@openharmony-rs/skiff';

@Entry
@Component
struct Page {
  controller: SkiffController = new SkiffController();

  build() {
    SkiffView({ src: 'https://servo.org', controller: this.controller })
  }
}
```

## Layout

| Path                       | Contents                                                                                  |
| -------------------------- | ----------------------------------------------------------------------------------------- |
| `crates/core`              | The Servo thread and its webviews: surfaces, vsync, input, soft keyboard. No Node-API.    |
| `crates/napi`              | `libskiff.so`: the Node-API functions and the XComponent callbacks.                       |
| `library`                  | The HAR: `SkiffView`, `SkiffController`, `SkiffRuntime`. Builds `crates/napi`.            |
| `entry`                    | A demo and test app with an address bar.                                                  |
| `entry/src/ohosTest`       | On-device tests of the HAR, run in the process of the demo app.                           |
| `justfile`                 | Recipes to format, lint, build, install and test; `just --list` shows them.               |
| `tools/sign-hap.py`        | Signs a HAP with the public OpenHarmony test keys.                                        |
| `tools/update-licenses.py` | Regenerates the license page of `servo:license` with the configuration in `tools/about/`. |

The repository root is also the hvigor project of the demo app, with `library` and `entry` as its
modules, so that DevEco Studio can open it. DevEco Studio also refuses a module named like the
project, which is the name of the directory the repository is cloned into.

Servo comes from the `servo` submodule, a commit of the `ohos-main` branch of
[servo-ohos](https://github.com/openharmony-rs/servo-ohos). Cargo does not apply the profiles,
`[patch]` entries and `[env]` settings of servo's workspace to dependents, so `Cargo.toml`,
`.cargo/config.toml`, `rust-toolchain.toml` and `rustfmt.toml` copy them. `Cargo.lock` started as a
copy of servo's to get the same dependency versions.

## Building

Needs rustup, `cargo install cargo-ohos just`, the OpenHarmony SDK for API 26 in
`$OHOS_BASE_SDK_HOME/26.0.0`, Java and command line tools (`ohpm`, `hvigorw`) that support it. Clone
with the submodule, which is shallow, and let `just install` build the demo app with hvigor, sign it
and install it with `hdc`:

```sh
git clone --recurse-submodules https://github.com/openharmony-rs/skiff
cd skiff
CARGO_TARGET_DIR=/path/to/target just install
```

hvigor runs cargo for the `library` module with the
[hvigor-cargo](https://github.com/openharmony-rs/hvigor-cargo) plugin from npm, which puts
`libskiff.so` and `libc++.so` into `library/libs` and from there into the HAR and the HAP. Both
build modes build the `release` cargo profile, since an unoptimized Servo is too slow to be useful.
Servo is built with the features `bundled`, `clipboard`, `js_jit`, `sqlite-backend` and
`webcrypto`, so WebGL, WebGPU and WebXR are not available.

Devices refuse unsigned HAPs. `sign-hap.py` signs with the OpenHarmony test keys from the SDK and a
release profile for the bundle of the HAP, which OpenHarmony devices accept.

## Demo app

```sh
hdc shell aa start -a EntryAbility -b org.openharmonyrs.skiff -U https://servo.org
```

Starting it again with `-U` loads the URL in the running app. The back key closes the soft
keyboard, goes back in the history, or exits, which saves cookies and other site data. Launch parameters, given as
`--ps <name> <value>` or `--psn <name>=<value>`:

| Parameter       | Effect                                                            |
| --------------- | ----------------------------------------------------------------- |
| `chrome none`   | Hides the address bar, so that the page fills the window.         |
| `prefs <json>`  | Servo preferences, e.g. `'{"dom_geolocation_enabled":true}'`.     |
| `log <filter>`  | Log filter in `env_logger` syntax, e.g. `warn,skiff_core=debug`.  |
| `eval <script>` | Runs the script after each page load and logs the result as JSON. |

The ⋮ menu of the address bar opens two pages:

- **Preferences** lists Servo's preferences, with a switch for all experimental web platform
  features on top. Changes on the *Live* tab apply to the pages loaded afterwards, those on the
  *After restart* tab when the app starts again, which *Restart now* does. The app remembers the
  changes and starts Servo with them, and then with the `prefs` launch parameter.
- **About** shows the versions of the app, the package and Servo, credits, and opens
  `servo:license`, the licenses of all components.

Servo logs to hilog with the domain `0xE0C3`, like servoshell. hilog drops debug messages unless
the device's log level is lowered with `hilog -b D`.

## API

`SkiffView` takes the URL to load first (`src`), a `SkiffController` and callbacks. If Servo
can't run, e.g. because its native library could not be loaded, `SkiffView` shows the reason instead
of the page and calls `onEngineError`, instead of throwing.

| ArkWeb                                   | Skiff                            | Notes                                  |
| ---------------------------------------- | -------------------------------- | -------------------------------------- |
| `Web({ src, controller })`               | `SkiffView({ src, controller })` |                                        |
| `loadUrl`, `refresh`                     | same                             |                                        |
| `backward`, `forward`                    | same                             |                                        |
| `accessBackward`, `accessForward`        | same                             | From the last history event.           |
| `getUrl`, `getTitle`                     | same                             | From the last URL and title events.    |
| `runJavaScript(script): Promise<string>` | same                             | Resolves with the result as JSON.      |
| `onPageBegin`, `onPageEnd`               | same                             |                                        |
| `onProgressChange`                       | same                             | Servo only reports 10, 60 and 100.     |
| `onTitleReceive`                         | same                             |                                        |
| `onConsole`                              | `onConsole({ level, message })`  |                                        |
| `onAlert`                                | `onAlert({ message })`           | The page does not wait for the app.    |
| `onRenderExited`                         | `onRenderExited({ reason })`     | Called when the page crashed.          |
| –                                        | `onUrlChange`, `onHistoryChange` |                                        |
| –                                        | `onEngineError({ message })`     | Servo can't run, crashed or shut down. |
| –                                        | `closeSoftKeyboard(): boolean`   | Call it first in `onBackPress`.        |

`SkiffRuntime.init({ preferences, logFilter })` starts Servo with other options than the defaults.
It has to be called before the first `SkiffView` appears, and returns why Servo could not start, or
`undefined`. `SkiffRuntime.shutdown()` stops Servo, which saves cookies and other site data to the
app's files directory; Servo writes them only then, so call it when the app exits.

`SkiffRuntime.preferences()` lists the preferences that an app can change, with their values, kinds
and whether they need a restart, and `SkiffRuntime.setPreference(name, value)` changes one while
Servo runs; it returns why it could not, or `undefined`. Which preferences need a restart comes from
an audit of where Servo reads them, in `crates/core/src/preferences.rs`. `SkiffRuntime.version` and
`SkiffRuntime.servoVersion()` are the versions of the package and of Servo.

`servo:license` shows the licenses of the components of the package. `tools/update-licenses.py`
generates it with [cargo-about](https://github.com/EmbarkStudios/cargo-about) into
`crates/core/resources/license.html`, which the library embeds compressed. Run it with
`just licenses` after changing dependencies. Besides the licenses that the crates declare, the page
has:

- the licenses of the C and C++ libraries that sys crates build, from `tools/about/servo.toml`,
  e.g. FreeType, HarfBuzz, zstd and AWS-LC
- the notices of the code in SpiderMonkey that is not under the MPL 2.0, from `licenses/` of
  `mozjs_sys` once mozjs ships them, and until then from `tools/about/mozjs_sys-<version>/`, which
  the prototype of mozjs' `etc/licenses.py` generated
- libc++, which the app ships as `libc++.so`, the Rust standard library and data files in Servo,
  from the partials in `tools/about/`

`tools/about/servo.toml` and the partials for libc++, the Rust standard library and data files are
meant for Servo, whose license page misses them too; `tools/about/overlay.toml` and `about.hbs` are
this package's. Apps using FreeType have to credit it in their documentation, as the About page of
the demo does.

## Tests

`entry/src/ohosTest` has [hypium](https://ohpm.openharmony.cn/#/en/detail/@ohos%2Fhypium)
tests that run on a device, in the process of the demo app. Their `TestAbility` shows a page that
the tests add `SkiffView` components to, one below the other or as tabs, and
`testability/Harness.ets` records the callbacks of each. Rendering is checked on screenshots.

| Suite                     | Covers                                                                                                                               |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `SkiffRuntime`            | Rejecting invalid preferences, starting Servo.                                                                                       |
| `SkiffViewApi`            | Load events, `runJavaScript`, loading before the component appears, history, `refresh`, console messages and alerts.                 |
| `SkiffRuntimePreferences` | Listing and changing preferences, their effect on pages, `servo:license`, the versions.                                              |
| `SkiffViewJavaScript`     | Concurrent calls, Unicode, values that JSON can't hold, calls that are pending while the page navigates, loads or goes away.         |
| `SkiffViewViewport`       | `devicePixelRatio`, the viewport size against the component, resizing, and the viewport `<meta>` element.                            |
| `SkiffViewLifecycle`      | Removing a `SkiffView`, reusing its controller, two at once, no events after removal.                                                |
| `SkiffViewRendering`      | The page on the screen, and two webviews animating at the same time.                                                                 |
| `SkiffViewTabs`           | Opening, switching and closing tabs, whether hidden or removed from the layout, and throttling hidden ones.                          |
| `SkiffViewInput`          | Tapping a link, scrolling, typing, closing the soft keyboard with the back key, and handing it over to an ArkUI text field and back. |
| `DemoApp`                 | The About page and the licenses, and the switch for experimental features, in the demo app.                                          |
| `SkiffRuntimeShutdown`    | Shutting Servo down.                                                                                                                 |

The suites share one Servo, so `SkiffRuntime` has to run first, `DemoApp`, which starts the demo
app in the same process, just before `SkiffRuntimeShutdown`, and that one last, as `List.test.ets`
does. `just test` builds both HAPs, signs and installs them, runs the tests and fails unless all
pass. The screen of the device has to be on and unlocked.

```sh
CARGO_TARGET_DIR=/path/to/target just [device=<serial>] test [-s class SkiffViewApi]
```

## Status

A prototype. Verified on a HiHope DAYU200 (OpenHarmony 7.0, API 26):
- rendering and page size, link navigation, back and forward, the back key, touch scrolling
- loading a URL into the running app
- typing with the soft keyboard, handing it over to an ArkUI text field and back, and key events
- `runJavaScript`, preferences, and returning from the background
- the error shown when `libskiff.so` can't be loaded, and cookies surviving an exit
- the on-device tests pass

Not done yet:

- `confirm()`, `prompt()`, `<select>`, file pickers, context menus, permission and authentication
  requests all get Servo's default response.
- `window.open()` and `target="_blank"` do nothing.
- No cookie, storage or cache management, no `onInterceptRequest`, no JavaScript proxies.
- Site data is only written when Servo shuts down, so it is lost when the system kills the app in
  the background. That needs a way to flush it in Servo.
- A `SkiffView` that disappears destroys its webview. A surface that is destroyed and created again
  while the component stays, is reattached, but that path is untested, as is recovering from a
  crash of the Servo thread.
- Servo sends load events and URL changes on separate channels. If a page finishes loading before
  its URL change arrives, `onPageBegin` and `onPageEnd` report the previous URL. Fixing that needs
  Servo to order them.
- Only arm64-v8a.

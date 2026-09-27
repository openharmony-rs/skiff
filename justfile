# Recipes for developing Skiff. `just --list` shows them.

set shell := ["bash", "-euo", "pipefail", "-c"]
set positional-arguments

# The device for hdc, e.g. `just device=<serial> test`. Empty for the only connected device.
device := ""
hdc := if device == "" { "hdc" } else { "hdc -t " + device }
outputs := "entry/build/default/outputs"

# Stable rustfmt takes these unstable options only on the command line.
# Formats the Rust code like servo's `./mach fmt`; `just fmt --check` only checks.
fmt *args:
    cargo fmt -p skiff-core -p skiff-napi -- --config unstable_features=true \
        --config binop_separator=Back --config imports_granularity=Module \
        --config group_imports=StdExternalCrate "$@"

# Lints the Rust code, with the host compilers of `library/hvigorfile.ts`.
clippy *args:
    CC=clang CXX=clang++ HOST_CC=clang HOST_CXX=clang++ HOST_CFLAGS= HOST_CXXFLAGS= \
        cargo ohos clippy --target aarch64 --sdk "$OHOS_BASE_SDK_HOME/26.0.0/native" \
        --download-prebuilt 19 --release -p skiff-core -p skiff-napi "$@"

# Regenerates the license page of `servo:license`. Run it after changing dependencies.
licenses *args:
    python3 tools/update-licenses.py "$@"

# Builds the demo app.
build:
    ohpm install --all
    hvigorw assembleHap --no-daemon -p buildMode=release

# Builds the on-device tests.
build-tests:
    hvigorw --mode module -p module=entry@ohosTest -p isOhosTest=true \
        -p product=default -p buildMode=test assembleHap --no-daemon

# Builds, signs and installs the demo app.
install: build (install-hap "default/entry-default")

# Fails unless all tests pass. The screen of the device has to be on and unlocked.
# Installs the app and its on-device tests and runs them, e.g. `just test -s class SkiffViewApi`.
test *args: install build-tests (install-hap "ohosTest/entry-ohosTest")
    {{ hdc }} shell aa test -b org.openharmonyrs.skiff -m entry_test -s unittest \
        /ets/testrunner/OpenHarmonyTestRunner -s timeout 30000 "$@" | tee >(cat >&2) | \
        grep OHOS_REPORT_RESULT | grep "Failure: 0, Error: 0" > /dev/null

# Signs a HAP with the OpenHarmony test keys and installs it. hdc exits with 0 even if the
# installation failed.
[private]
install-hap hap:
    python3 tools/sign-hap.py {{ outputs }}/{{ hap }}-unsigned.hap {{ outputs }}/{{ hap }}-signed.hap
    {{ hdc }} install -r {{ outputs }}/{{ hap }}-signed.hap | tee >(cat >&2) | \
        grep "install bundle successfully" > /dev/null

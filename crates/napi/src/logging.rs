/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

use std::sync::{LazyLock, Once};
use std::thread;

use log::{LevelFilter, error};

/// The hilog domain, shared with servoshell so that the same log filters work for both.
const LOG_DOMAIN: u16 = 0xE0C3;

static LOGGER: LazyLock<hilog::Logger> = LazyLock::new(|| {
    let mut builder = hilog::Builder::new();
    builder.set_domain(hilog::LogDomain::new(LOG_DOMAIN));
    for module in [
        "skiff",
        "skiff_core",
        "script::dom::bindings::error",
        "servo_constellation::constellation",
    ] {
        builder.filter_module(module, LevelFilter::Info);
    }
    builder.filter_level(LevelFilter::Warn).build()
});

/// Routes `log` to hilog and logs panics. Only the first call has an effect.
pub(crate) fn init() {
    static ONCE: Once = Once::new();
    ONCE.call_once(|| {
        let logger: &'static hilog::Logger = &LOGGER;
        if log::set_logger(logger).is_ok() {
            log::set_max_level(logger.filter());
        }
        std::panic::set_hook(Box::new(|info| {
            let thread = thread::current();
            error!(
                "Panic on thread {}: {info}",
                thread.name().unwrap_or("<unnamed>")
            );
        }));
    });
}

/// Replaces the log filter with one in `env_logger` syntax.
pub(crate) fn set_filter(filter: &str) {
    let mut builder = env_filter::Builder::new();
    match builder.try_parse(filter) {
        Ok(builder) => {
            let filter = builder.build();
            log::set_max_level(filter.filter());
            LOGGER.set_filter(filter);
        },
        Err(error) => error!("Invalid log filter {filter:?}: {error}"),
    }
}

/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

//! Servo webviews for OpenHarmony apps, independent of how the app talks to native code.
//!
//! Servo and its webviews are `!Send`, so they live on a dedicated thread that [`start`] spawns.
//! All other functions post a message to that thread and return immediately, except
//! [`detach_surface`], [`blur`], [`set_preference`] and [`shutdown`], which wait for the thread.
//! Each webview reports what happens to it through the [`EventSink`] it was created with.

mod delegate;
mod engine;
mod ime;
mod native_window;
mod preferences;
mod protocol;
mod vsync;

pub use engine::{
    EngineOptions, EventSink, JavaScriptCallback, TouchPhase, WebViewEvent, WebViewId,
    attach_surface, blur, create_webview, destroy_webview, detach_surface, dismiss_soft_keyboard,
    evaluate_javascript, go_back, go_forward, key_event, load_url, reload, resize_surface,
    set_app_visible, set_preference, set_surface_visible, set_visible, shutdown, start,
    touch_event,
};
pub use native_window::NativeWindow;
pub use preferences::{
    EXPERIMENTAL_PREFERENCES, PreferenceInfo, check_preference, preference_to_json, preferences,
};
pub use servo::{PrefValue, Preferences, UserAgentPlatform};
// Compiles the resources that Servo reads at runtime into the library.
use servo_default_resources as _;

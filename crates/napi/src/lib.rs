/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

//! `libskiff.so`, the Node-API module behind the `SkiffView` ArkTS component.
//!
//! ArkTS creates a webview with [`create_web_view`] and then an XComponent with the id
//! `skiff-<webview id>` and the library name `skiff`. The XComponent calls the module
//! initializer again, this time with the native XComponent, whose surface and input callbacks
//! [`xcomponent`] forwards to the webview.

mod logging;
mod xcomponent;

use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicU32, Ordering};

use log::{error, warn};
use napi_derive_ohos::napi;
use napi_ohos::bindgen_prelude::{Function, JsObjectValue, Object};
use napi_ohos::threadsafe_function::{ThreadsafeFunction, ThreadsafeFunctionCallMode};
use napi_ohos::{Env, Error, Status};
use skiff_core::{
    EngineOptions, PrefValue, Preferences, UserAgentPlatform, WebViewEvent, preference_to_json,
};

#[napi(module_exports)]
fn module_init(exports: Object, env: Env) -> napi_ohos::Result<()> {
    logging::init();
    if let Ok(xcomponent) = exports.get_named_property::<Object>("__NATIVE_XCOMPONENT_OBJ__") {
        xcomponent::register(&env, &xcomponent)?;
    }
    Ok(())
}

#[napi(object)]
pub struct InitOptions {
    /// Servo preferences as a JSON object, e.g. `{"js_ion_enabled": false}`.
    pub preferences: Option<String>,
    /// A log filter in `env_logger` syntax, e.g. `warn,servo=debug`.
    pub log_filter: Option<String>,
}

/// Starts Servo. Later calls have no effect.
#[napi]
pub fn init(options: InitOptions) -> napi_ohos::Result<()> {
    if let Some(filter) = &options.log_filter {
        logging::set_filter(filter);
    }
    let mut preferences = Preferences::default();
    preferences.set_value("viewport_meta_enabled", PrefValue::Bool(true));
    if let Some(json) = &options.preferences {
        apply_preferences(&mut preferences, json)?;
    }
    let started = skiff_core::start(EngineOptions {
        config_dir: config_dir()?,
        preferences,
        hidpi_scale_factor: display_density(),
    });
    if !started {
        warn!("Servo was already started");
    }
    Ok(())
}

#[napi(object)]
pub struct JsWebViewEvent {
    pub kind: String,
    pub url: Option<String>,
    pub title: Option<String>,
    pub progress: Option<u32>,
    pub can_go_back: Option<bool>,
    pub can_go_forward: Option<bool>,
    pub level: Option<String>,
    pub message: Option<String>,
}

impl JsWebViewEvent {
    fn new(kind: &str) -> Self {
        Self {
            kind: kind.into(),
            url: None,
            title: None,
            progress: None,
            can_go_back: None,
            can_go_forward: None,
            level: None,
            message: None,
        }
    }
}

impl From<WebViewEvent> for JsWebViewEvent {
    fn from(event: WebViewEvent) -> Self {
        match event {
            WebViewEvent::UrlChanged(url) => Self {
                url: Some(url),
                ..Self::new("urlChanged")
            },
            WebViewEvent::TitleChanged(title) => Self {
                title: Some(title),
                ..Self::new("titleChanged")
            },
            WebViewEvent::LoadStarted(url) => Self {
                url: Some(url),
                ..Self::new("loadStarted")
            },
            WebViewEvent::LoadFinished(url) => Self {
                url: Some(url),
                ..Self::new("loadFinished")
            },
            WebViewEvent::Progress(progress) => Self {
                progress: Some(progress),
                ..Self::new("progress")
            },
            WebViewEvent::HistoryChanged {
                can_go_back,
                can_go_forward,
            } => Self {
                can_go_back: Some(can_go_back),
                can_go_forward: Some(can_go_forward),
                ..Self::new("historyChanged")
            },
            WebViewEvent::ConsoleMessage { level, message } => Self {
                level: Some(level.as_str().to_lowercase()),
                message: Some(message),
                ..Self::new("console")
            },
            WebViewEvent::Alert(message) => Self {
                message: Some(message),
                ..Self::new("alert")
            },
            WebViewEvent::Crashed(message) => Self {
                message: Some(message),
                ..Self::new("crashed")
            },
            WebViewEvent::EngineStopped(message) => Self {
                message: Some(message),
                ..Self::new("engineStopped")
            },
        }
    }
}

static NEXT_WEBVIEW_ID: AtomicU32 = AtomicU32::new(1);

/// Creates a webview that reports its events to `on_event` and returns its id.
#[napi]
pub fn create_web_view(
    url: Option<String>,
    on_event: Function<JsWebViewEvent, ()>,
) -> napi_ohos::Result<u32> {
    let id = NEXT_WEBVIEW_ID.fetch_add(1, Ordering::Relaxed);
    let on_event: ThreadsafeFunction<JsWebViewEvent, (), JsWebViewEvent, Status, false> =
        on_event.build_threadsafe_function().build()?;
    skiff_core::create_webview(
        id,
        url,
        Arc::new(move |event| {
            let status = on_event.call(event.into(), ThreadsafeFunctionCallMode::NonBlocking);
            if status != Status::Ok {
                error!("Delivering an event of webview {id} failed: {status}");
            }
        }),
    );
    Ok(id)
}

/// Shuts Servo down, which saves cookies and other site data. Servo can't be started again.
#[napi]
pub fn shutdown() {
    skiff_core::shutdown();
}

#[napi]
pub fn destroy_web_view(id: u32) {
    skiff_core::destroy_webview(id);
}

#[napi]
pub fn load_url(id: u32, url: String) {
    skiff_core::load_url(id, url);
}

#[napi]
pub fn reload(id: u32) {
    skiff_core::reload(id);
}

#[napi]
pub fn go_back(id: u32) {
    skiff_core::go_back(id);
}

#[napi]
pub fn go_forward(id: u32) {
    skiff_core::go_forward(id);
}

/// Tells whether the app is in the foreground.
#[napi]
pub fn set_app_visible(visible: bool) {
    skiff_core::set_app_visible(visible);
}

/// Closes the soft keyboard if the webview has it, and returns whether it had.
#[napi]
pub fn dismiss_soft_keyboard(id: u32) -> bool {
    skiff_core::dismiss_soft_keyboard(id)
}

#[napi]
pub fn set_visible(id: u32, visible: bool) {
    skiff_core::set_visible(id, visible);
}

#[napi(object)]
pub struct JavaScriptResult {
    /// The result as JSON.
    pub result: Option<String>,
    pub error: Option<String>,
}

#[napi]
pub fn evaluate_java_script(
    id: u32,
    script: String,
    callback: Function<JavaScriptResult, ()>,
) -> napi_ohos::Result<()> {
    let callback: ThreadsafeFunction<JavaScriptResult, (), JavaScriptResult, Status, false> =
        callback.build_threadsafe_function().build()?;
    skiff_core::evaluate_javascript(
        id,
        script,
        Box::new(move |result| {
            let (result, error) = match result {
                Ok(result) => (Some(result), None),
                Err(error) => (None, Some(error)),
            };
            let status = callback.call(
                JavaScriptResult { result, error },
                ThreadsafeFunctionCallMode::NonBlocking,
            );
            if status != Status::Ok {
                error!("Delivering a JavaScript result of webview {id} failed: {status}");
            }
        }),
    );
    Ok(())
}

fn apply_preferences(preferences: &mut Preferences, json: &str) -> napi_ohos::Result<()> {
    let values: serde_json::Map<String, serde_json::Value> = serde_json::from_str(json)
        .map_err(|error| Error::from_reason(format!("Invalid preferences: {error}")))?;
    for (name, value) in values {
        let value = preference_value(&name, &value)?;
        preferences.set_value(&name, value);
    }
    Ok(())
}

/// Converts a JSON value to a value of the preference.
fn preference_value(name: &str, value: &serde_json::Value) -> napi_ohos::Result<PrefValue> {
    let value = PrefValue::try_from(value)
        .map_err(|error| Error::from_reason(format!("Invalid value for {name}: {error}")))?;
    skiff_core::check_preference(name, value).map_err(Error::from_reason)
}

#[napi(object)]
pub struct Preference {
    pub name: String,
    /// `boolean`, `integer`, `unsigned` for non-negative integers, or `string`.
    pub kind: String,
    /// The value that Servo uses as JSON.
    pub value: String,
    pub default_value: String,
    /// Whether a change only takes effect when Servo starts.
    pub needs_restart: bool,
    pub experimental: bool,
}

/// The preferences that an app can change, with the values that Servo uses.
#[napi]
pub fn preferences() -> Vec<Preference> {
    skiff_core::preferences()
        .into_iter()
        .map(|preference| Preference {
            name: preference.name.into(),
            kind: match preference.default_value {
                PrefValue::Bool(_) => "boolean",
                PrefValue::Int(_) => "integer",
                PrefValue::UInt(_) => "unsigned",
                _ => "string",
            }
            .into(),
            value: preference_to_json(&preference.value).to_string(),
            default_value: preference_to_json(&preference.default_value).to_string(),
            needs_restart: preference.needs_restart,
            experimental: preference.experimental,
        })
        .collect()
}

/// Changes a preference of the running Servo to `value`, given as JSON.
#[napi]
pub fn set_preference(name: String, value: String) -> napi_ohos::Result<()> {
    let value: serde_json::Value = serde_json::from_str(&value)
        .map_err(|error| Error::from_reason(format!("Invalid value for {name}: {error}")))?;
    let value = preference_value(&name, &value)?;
    skiff_core::set_preference(&name, value).map_err(Error::from_reason)
}

/// The version of Servo, e.g. `0.5.0`.
#[napi]
pub fn servo_version() -> String {
    let user_agent = UserAgentPlatform::default().to_user_agent_string();
    user_agent
        .split(' ')
        .find_map(|part| part.strip_prefix("Servo/"))
        .unwrap_or("unknown")
        .into()
}

/// The directory for Servo's configuration and site data, such as cookies and local storage. It is
/// in the files directory of the app, which the system does not clean up, unlike the cache.
fn config_dir() -> napi_ohos::Result<PathBuf> {
    use ohos_abilitykit_sys::runtime::application_context::OH_AbilityRuntime_ApplicationContextGetFilesDir;

    let mut buffer = vec![0u8; 1024];
    let mut length = 0;
    // SAFETY: The buffer is as large as the size passed along.
    unsafe {
        OH_AbilityRuntime_ApplicationContextGetFilesDir(
            buffer.as_mut_ptr().cast(),
            buffer.len() as i32,
            &mut length,
        )
    }
    .map_err(|error| {
        Error::from_reason(format!("Getting the files directory failed: {error:?}"))
    })?;
    buffer.truncate(length as usize);
    let files_dir = String::from_utf8(buffer)
        .map_err(|_| Error::from_reason("The files directory is not UTF-8"))?;
    let config_dir = PathBuf::from(files_dir).join("servo");
    std::fs::create_dir_all(&config_dir).map_err(|error| {
        Error::from_reason(format!("Creating {} failed: {error}", config_dir.display()))
    })?;
    Ok(config_dir)
}

fn display_density() -> f32 {
    use ohos_window_manager_sys::display_manager::OH_NativeDisplayManager_GetDefaultDisplayDensityPixels;

    let mut density = 1.0;
    // SAFETY: The function writes a single f32.
    if let Err(error) =
        unsafe { OH_NativeDisplayManager_GetDefaultDisplayDensityPixels(&mut density) }
    {
        warn!("Getting the display density failed: {error:?}");
        return 1.0;
    }
    density
}

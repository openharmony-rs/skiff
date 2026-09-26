/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

use servo::{PrefValue, Preferences, prefs};

/// The preferences of experimental web platform features, the same as servoshell's.
pub const EXPERIMENTAL_PREFERENCES: &[&str] = &[
    "dom_async_clipboard_enabled",
    "dom_exec_command_enabled",
    "dom_fontface_enabled",
    "dom_indexeddb_enabled",
    "dom_intersection_observer_enabled",
    "dom_navigator_protocol_handlers_enabled",
    "dom_notification_enabled",
    "dom_offscreen_canvas_enabled",
    "dom_permissions_enabled",
    "dom_sanitizer_enabled",
    "dom_storage_manager_api_enabled",
    "dom_webgl2_enabled",
    "dom_webgpu_enabled",
    "layout_css_alpha_color_function_enabled",
    "layout_css_attr_enabled",
    "layout_css_ellipse_corners_enabled",
    "layout_css_progress_function_enabled",
    "layout_columns_enabled",
    "layout_container_queries_enabled",
    "layout_variable_fonts_enabled",
];

/// A preference, as an app shows it to let the user change it.
pub struct PreferenceInfo {
    pub name: &'static str,
    /// The value that Servo uses, or the default before Servo started.
    pub value: PrefValue,
    pub default_value: PrefValue,
    /// Whether a change only takes effect when Servo starts, rather than for the pages that load
    /// after it.
    pub needs_restart: bool,
    pub experimental: bool,
}

/// The preferences that can be changed. It leaves out those that the webview does not use.
pub fn preferences() -> Vec<PreferenceInfo> {
    let current = prefs::get();
    let defaults = Preferences::default();
    Preferences::all_fields()
        .into_iter()
        .filter(|name| !UNUSED.contains(name))
        .filter_map(|name| {
            let default_value = defaults.get_value(name);
            if matches!(default_value, PrefValue::Array(_) | PrefValue::Float(_)) {
                return None;
            }
            Some(PreferenceInfo {
                name,
                value: current.get_value(name),
                default_value,
                needs_restart: RESTART.contains(&name),
                experimental: EXPERIMENTAL_PREFERENCES.contains(&name),
            })
        })
        .collect()
}

/// Returns the value converted to the type of the preference, or why it does not fit.
pub fn check_preference(name: &str, value: PrefValue) -> Result<PrefValue, String> {
    if !Preferences::exists(name) {
        return Err(format!("Unknown preference {name}"));
    }
    match (Preferences::default().get_value(name), value) {
        (PrefValue::Bool(_), value @ PrefValue::Bool(_)) |
        (PrefValue::Int(_), value @ PrefValue::Int(_)) |
        (PrefValue::UInt(_), value @ PrefValue::UInt(_)) |
        (PrefValue::Str(_), value @ PrefValue::Str(_)) => Ok(value),
        (PrefValue::UInt(_), PrefValue::Int(value)) if value >= 0 => {
            Ok(PrefValue::UInt(value as u64))
        },
        (default, value) => Err(format!(
            "Preference {name} takes {}, not {}",
            type_name(&default),
            preference_to_json(&value)
        )),
    }
}

pub fn preference_to_json(value: &PrefValue) -> serde_json::Value {
    use serde_json::Value;
    match value {
        PrefValue::Bool(value) => Value::Bool(*value),
        PrefValue::Int(value) => Value::from(*value),
        PrefValue::UInt(value) => Value::from(*value),
        PrefValue::Float(value) => Value::from(*value),
        PrefValue::Str(value) => Value::String(value.clone()),
        PrefValue::Array(values) => Value::Array(values.iter().map(preference_to_json).collect()),
    }
}

fn type_name(value: &PrefValue) -> &'static str {
    match value {
        PrefValue::Bool(_) => "a boolean",
        PrefValue::Int(_) => "an integer",
        PrefValue::UInt(_) => "a non-negative integer",
        PrefValue::Str(_) => "a string",
        PrefValue::Float(_) => "a number",
        PrefValue::Array(_) => "an array",
    }
}

/// Preferences that only servoshell or debug builds of SpiderMonkey read.
const UNUSED: &[&str] = &[
    "dom_webxr_glwindow_cubemap",
    "dom_webxr_glwindow_enabled",
    "dom_webxr_glwindow_left_right",
    "dom_webxr_glwindow_red_cyan",
    "dom_webxr_glwindow_spherical",
    "dom_webxr_openxr_enabled",
    "js_mem_gc_zeal_frequency",
    "js_mem_gc_zeal_level",
    "log_filter",
];

/// Preferences that Servo reads when it starts, or keeps in threads, JavaScript runtimes and caches
/// that live as long as the process, so a change needs the app to restart.
const RESTART: &[&str] = &[
    // Turning it off while a webview uses accessibility fails an assertion.
    "accessibility_enabled",
    "devtools_server_enabled",
    "devtools_server_listen_address",
    "dom_webgpu_wgpu_backend",
    "fonts_default",
    "fonts_monospace",
    "fonts_sans_serif",
    "fonts_serif",
    "gfx_precache_shaders",
    "gfx_subpixel_text_antialiasing_enabled",
    "gfx_text_antialiasing_enabled",
    "gfx_texture_swizzling_enabled",
    "intl_locale_override",
    "js_asmjs_enabled",
    "js_baseline_interpreter_enabled",
    "js_baseline_jit_enabled",
    "js_baseline_jit_unsafe_eager_compilation_enabled",
    "js_disable_jit",
    "js_ion_enabled",
    "js_ion_unsafe_eager_compilation_enabled",
    "js_mem_gc_compacting_enabled",
    "js_mem_gc_empty_chunk_count_min",
    "js_mem_gc_high_frequency_heap_growth_max",
    "js_mem_gc_high_frequency_heap_growth_min",
    "js_mem_gc_high_frequency_high_limit_mb",
    "js_mem_gc_high_frequency_low_limit_mb",
    "js_mem_gc_high_frequency_time_limit_ms",
    "js_mem_gc_incremental_enabled",
    "js_mem_gc_incremental_slice_ms",
    "js_mem_gc_low_frequency_heap_growth",
    "js_mem_gc_per_zone_enabled",
    "js_mem_max",
    "js_native_regex_enabled",
    "js_offthread_compilation_enabled",
    "js_wasm_baseline_enabled",
    "js_wasm_enabled",
    "js_wasm_ion_enabled",
    "layout_style_sharing_cache_enabled",
    "layout_threads",
    "media_glvideo_enabled",
    "network_connection_timeout",
    "network_http_cache_size",
    "network_http_disk_cache",
    "network_http_disk_cache_size",
    "network_http_no_proxy",
    "network_http_proxy_uri",
    "network_https_proxy_uri",
    "network_use_webpki_roots",
    "perf_thread_boost_enabled",
    "storage_ohos_rdb_backend_enabled",
    "thread_pool_async_runtime_workers_max",
    "thread_pool_fallback_workers",
    "thread_pool_webrender_workers_max",
    "thread_pool_workers_max",
];

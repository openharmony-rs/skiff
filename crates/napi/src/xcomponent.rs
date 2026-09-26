/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

//! Forwards the surface, focus and input callbacks of `SkiffView`'s XComponents to their webviews.
//!
//! ArkUI calls the callbacks on the UI thread with a live XComponent and, where there is one, its
//! surface, which is all their safety requirements.

use std::ffi::{CStr, c_void};
use std::mem::MaybeUninit;
use std::ptr::NonNull;
use std::sync::Mutex;

use dpi::PhysicalSize;
use log::{debug, error, warn};
use napi_ohos::bindgen_prelude::Object;
use napi_ohos::{Env, Error, JsValue};
use skiff_core::{NativeWindow, TouchPhase, WebViewId};
use xcomponent_sys::keyboard_types_compat::{KeyEventConverter, ModifierState};
use xcomponent_sys::{
    OH_NativeXComponent, OH_NativeXComponent_Callback, OH_NativeXComponent_GetKeyEvent,
    OH_NativeXComponent_GetKeyEventAction, OH_NativeXComponent_GetKeyEventCapsLockState,
    OH_NativeXComponent_GetKeyEventCode, OH_NativeXComponent_GetKeyEventModifierKeyStates,
    OH_NativeXComponent_GetKeyEventNumLockState, OH_NativeXComponent_GetKeyEventScrollLockState,
    OH_NativeXComponent_GetTouchEvent, OH_NativeXComponent_GetXComponentId,
    OH_NativeXComponent_GetXComponentSize, OH_NativeXComponent_KeyAction,
    OH_NativeXComponent_KeyCode, OH_NativeXComponent_KeyEvent,
    OH_NativeXComponent_RegisterBlurEventCallback, OH_NativeXComponent_RegisterCallback,
    OH_NativeXComponent_RegisterKeyEventCallback, OH_NativeXComponent_RegisterSurfaceHideCallback,
    OH_NativeXComponent_RegisterSurfaceShowCallback, OH_NativeXComponent_TouchEvent,
    OH_NativeXComponent_TouchEventType, OH_XCOMPONENT_ID_LEN_MAX,
};

/// The XComponent of a webview has the id `skiff-<webview id>`.
const ID_PREFIX: &str = "skiff-";

static mut CALLBACKS: OH_NativeXComponent_Callback = OH_NativeXComponent_Callback {
    OnSurfaceCreated: Some(on_surface_created),
    OnSurfaceChanged: Some(on_surface_changed),
    OnSurfaceDestroyed: Some(on_surface_destroyed),
    DispatchTouchEvent: Some(on_touch_event),
};

static KEY_EVENT_CONVERTER: Mutex<KeyEventConverter> = Mutex::new(KeyEventConverter::new());

pub(crate) fn register(env: &Env, xcomponent: &Object) -> napi_ohos::Result<()> {
    let mut native: *mut OH_NativeXComponent = std::ptr::null_mut();
    // SAFETY: ArkUI wraps the native XComponent in the `__NATIVE_XCOMPONENT_OBJ__` object.
    let status = unsafe {
        napi_ohos::sys::napi_unwrap(
            env.raw(),
            xcomponent.raw(),
            (&raw mut native).cast::<*mut c_void>(),
        )
    };
    if status != 0 || native.is_null() {
        return Err(Error::from_reason("Could not unwrap the native XComponent"));
    }
    // SAFETY: `native` is a live XComponent, and the callbacks are never modified or freed.
    let result = unsafe { OH_NativeXComponent_RegisterCallback(native, &raw mut CALLBACKS) };
    if result != 0 {
        return Err(Error::from_reason(format!(
            "Registering the XComponent callbacks failed: {result}"
        )));
    }
    // SAFETY: `native` is a live XComponent.
    let results = unsafe {
        [
            OH_NativeXComponent_RegisterKeyEventCallback(native, Some(on_key_event)),
            OH_NativeXComponent_RegisterSurfaceShowCallback(native, Some(on_surface_show)),
            OH_NativeXComponent_RegisterSurfaceHideCallback(native, Some(on_surface_hide)),
            OH_NativeXComponent_RegisterBlurEventCallback(native, Some(on_blur)),
        ]
    };
    if results.iter().any(|result| *result != 0) {
        warn!("Registering some XComponent callbacks failed: {results:?}");
    }
    Ok(())
}

/// Returns the webview that the XComponent shows.
///
/// # Safety
///
/// `xcomponent` must be a live XComponent.
unsafe fn webview_id(xcomponent: *mut OH_NativeXComponent) -> Option<WebViewId> {
    let mut buffer = [0u8; OH_XCOMPONENT_ID_LEN_MAX as usize + 1];
    let mut size = buffer.len() as u64;
    // SAFETY: The caller guarantees that `xcomponent` is live, and `buffer` holds `size` bytes.
    let result = unsafe {
        OH_NativeXComponent_GetXComponentId(xcomponent, buffer.as_mut_ptr().cast(), &raw mut size)
    };
    if result != 0 {
        error!("Getting the XComponent id failed: {result}");
        return None;
    }
    let id = CStr::from_bytes_until_nul(&buffer)
        .ok()
        .and_then(|id| id.to_str().ok());
    let webview_id = id
        .and_then(|id| id.strip_prefix(ID_PREFIX))
        .and_then(|id| id.parse().ok());
    if webview_id.is_none() {
        error!("The XComponent {id:?} does not belong to a webview");
    }
    webview_id
}

/// # Safety
///
/// `xcomponent` and `window` must be a live XComponent and its surface.
unsafe fn surface_size(
    xcomponent: *mut OH_NativeXComponent,
    window: *mut c_void,
) -> Option<PhysicalSize<u32>> {
    let (mut width, mut height) = (0u64, 0u64);
    // SAFETY: Guaranteed by the caller.
    let result = unsafe {
        OH_NativeXComponent_GetXComponentSize(xcomponent, window, &raw mut width, &raw mut height)
    };
    if result != 0 {
        error!("Getting the XComponent size failed: {result}");
        return None;
    }
    Some(PhysicalSize::new(
        width.try_into().ok()?,
        height.try_into().ok()?,
    ))
}

/// # Safety
///
/// `xcomponent` and `window` must be a live XComponent and its surface.
unsafe extern "C" fn on_surface_created(xcomponent: *mut OH_NativeXComponent, window: *mut c_void) {
    // SAFETY: Guaranteed by the caller.
    let (Some(id), Some(size)) = (unsafe { webview_id(xcomponent) }, unsafe {
        surface_size(xcomponent, window)
    }) else {
        return;
    };
    // SAFETY: The surface of a live XComponent is a live native window.
    let Some(window) =
        NonNull::new(window).and_then(|window| unsafe { NativeWindow::from_raw(window) })
    else {
        error!("The surface of webview {id} has no usable native window");
        return;
    };
    debug!("Surface of webview {id} created at {size:?}");
    skiff_core::attach_surface(id, window, size);
}

/// # Safety
///
/// `xcomponent` and `window` must be a live XComponent and its surface.
unsafe extern "C" fn on_surface_changed(xcomponent: *mut OH_NativeXComponent, window: *mut c_void) {
    // SAFETY: Guaranteed by the caller.
    let (Some(id), Some(size)) = (unsafe { webview_id(xcomponent) }, unsafe {
        surface_size(xcomponent, window)
    }) else {
        return;
    };
    debug!("Surface of webview {id} changed to {size:?}");
    skiff_core::resize_surface(id, size);
}

/// # Safety
///
/// `xcomponent` must be a live XComponent.
unsafe extern "C" fn on_surface_destroyed(
    xcomponent: *mut OH_NativeXComponent,
    _window: *mut c_void,
) {
    // SAFETY: Guaranteed by the caller.
    if let Some(id) = unsafe { webview_id(xcomponent) } {
        debug!("Surface of webview {id} destroyed");
        skiff_core::detach_surface(id);
    }
}

/// # Safety
///
/// `xcomponent` must be a live XComponent.
unsafe extern "C" fn on_surface_show(xcomponent: *mut OH_NativeXComponent, _window: *mut c_void) {
    // SAFETY: Guaranteed by the caller.
    if let Some(id) = unsafe { webview_id(xcomponent) } {
        debug!("Surface of webview {id} shown");
        skiff_core::set_surface_visible(id, true);
    }
}

/// # Safety
///
/// `xcomponent` must be a live XComponent.
unsafe extern "C" fn on_surface_hide(xcomponent: *mut OH_NativeXComponent, _window: *mut c_void) {
    // SAFETY: Guaranteed by the caller.
    if let Some(id) = unsafe { webview_id(xcomponent) } {
        debug!("Surface of webview {id} hidden");
        skiff_core::set_surface_visible(id, false);
    }
}

/// # Safety
///
/// `xcomponent` must be a live XComponent.
unsafe extern "C" fn on_blur(xcomponent: *mut OH_NativeXComponent, _window: *mut c_void) {
    // SAFETY: Guaranteed by the caller.
    if let Some(id) = unsafe { webview_id(xcomponent) } {
        debug!("Webview {id} lost the focus");
        // Before returning, so that the component that gets the focus can use the soft keyboard.
        skiff_core::blur(id);
    }
}

/// # Safety
///
/// `xcomponent` and `window` must be a live XComponent and its surface.
unsafe extern "C" fn on_touch_event(xcomponent: *mut OH_NativeXComponent, window: *mut c_void) {
    // SAFETY: Guaranteed by the caller.
    let Some(id) = (unsafe { webview_id(xcomponent) }) else {
        return;
    };
    let mut event = MaybeUninit::<OH_NativeXComponent_TouchEvent>::uninit();
    // SAFETY: Guaranteed by the caller, and `event` is large enough.
    let result =
        unsafe { OH_NativeXComponent_GetTouchEvent(xcomponent, window, event.as_mut_ptr()) };
    if result != 0 {
        error!("Getting the touch event failed: {result}");
        return;
    }
    let event = event.as_ptr();
    // SAFETY: The successful call above initialized the fields of the changed touch point. The
    // entries of `touchPoints` beyond `numPoints` might not be, so the event isn't read as a whole.
    let (type_, pointer_id, x, y) =
        unsafe { ((*event).type_, (*event).id, (*event).x, (*event).y) };
    let phase = match type_ {
        OH_NativeXComponent_TouchEventType::OH_NATIVEXCOMPONENT_DOWN => TouchPhase::Down,
        OH_NativeXComponent_TouchEventType::OH_NATIVEXCOMPONENT_MOVE => TouchPhase::Move,
        OH_NativeXComponent_TouchEventType::OH_NATIVEXCOMPONENT_UP => TouchPhase::Up,
        OH_NativeXComponent_TouchEventType::OH_NATIVEXCOMPONENT_CANCEL => TouchPhase::Cancel,
        other => {
            warn!("Ignoring touch event of type {other:?}");
            return;
        },
    };
    skiff_core::touch_event(id, phase, pointer_id, x, y);
}

/// # Safety
///
/// `xcomponent` must be a live XComponent that is dispatching a key event.
unsafe extern "C" fn on_key_event(xcomponent: *mut OH_NativeXComponent, _window: *mut c_void) {
    // See <https://docs.rs/arkui-sys/latest/arkui_sys/ui_input_event/struct.ArkUI_ModifierKeyName.html>.
    const MODIFIER_KEY_CTRL: u64 = 1;
    const MODIFIER_KEY_SHIFT: u64 = 2;
    const MODIFIER_KEY_ALT: u64 = 4;

    // SAFETY: Guaranteed by the caller.
    let Some(id) = (unsafe { webview_id(xcomponent) }) else {
        return;
    };
    let mut event: *mut OH_NativeXComponent_KeyEvent = std::ptr::null_mut();
    let mut action = OH_NativeXComponent_KeyAction::OH_NATIVEXCOMPONENT_KEY_ACTION_UNKNOWN;
    let mut code = OH_NativeXComponent_KeyCode::KEY_UNKNOWN;
    let mut modifier_bits: u64 = 0;
    let (mut caps_lock, mut num_lock, mut scroll_lock) = (false, false, false);
    // SAFETY: Guaranteed by the caller. The key event lives until this callback returns.
    unsafe {
        if OH_NativeXComponent_GetKeyEvent(xcomponent, &raw mut event) != 0 ||
            OH_NativeXComponent_GetKeyEventAction(event, &raw mut action) != 0 ||
            OH_NativeXComponent_GetKeyEventCode(event, &raw mut code) != 0
        {
            error!("Getting the key event failed");
            return;
        }
        OH_NativeXComponent_GetKeyEventModifierKeyStates(event, &raw mut modifier_bits);
        OH_NativeXComponent_GetKeyEventCapsLockState(event, &raw mut caps_lock);
        OH_NativeXComponent_GetKeyEventNumLockState(event, &raw mut num_lock);
        OH_NativeXComponent_GetKeyEventScrollLockState(event, &raw mut scroll_lock);
    }
    let modifiers = ModifierState {
        shift: modifier_bits & MODIFIER_KEY_SHIFT != 0,
        ctrl: modifier_bits & MODIFIER_KEY_CTRL != 0,
        alt: modifier_bits & MODIFIER_KEY_ALT != 0,
        meta: None,
        caps_lock,
        num_lock,
        scroll_lock,
    };
    let converted = KEY_EVENT_CONVERTER
        .lock()
        .unwrap()
        .convert(action, code, modifiers);
    match converted {
        Some(event) => skiff_core::key_event(id, event),
        None => debug!("Ignoring key event {action:?} {code:?}"),
    }
}

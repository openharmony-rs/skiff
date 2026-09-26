/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

use std::ffi::c_void;
use std::ptr::NonNull;

use log::{error, warn};
use ohos_window_sys::native_buffer::native_buffer::OH_NativeBuffer_Usage;
use ohos_window_sys::native_window::{
    NativeWindowOperation, OH_NativeWindow_NativeObjectReference,
    OH_NativeWindow_NativeObjectUnreference, OH_NativeWindow_NativeWindowHandleOpt,
};
use raw_window_handle::{OhosNdkWindowHandle, RawWindowHandle, WindowHandle};

/// A reference to an `OHNativeWindow` that a webview renders into. The window stays alive while
/// this value exists, even if the system destroyed the surface it belongs to.
#[derive(Debug)]
pub struct NativeWindow(NonNull<c_void>);

// SAFETY: Native windows are reference counted objects that can be used from any thread, and this
// value holds a reference of its own.
unsafe impl Send for NativeWindow {}

impl NativeWindow {
    /// Takes a reference to `window`.
    ///
    /// # Safety
    ///
    /// `window` must point to a live `OHNativeWindow`.
    pub unsafe fn from_raw(window: NonNull<c_void>) -> Option<Self> {
        // SAFETY: The caller guarantees that `window` is a live native window.
        let result = unsafe { OH_NativeWindow_NativeObjectReference(window.as_ptr()) };
        if result != 0 {
            error!("Referencing a native window failed: {result}");
            return None;
        }
        Some(Self(window))
    }

    /// Borrows the window for creating a rendering surface. Whoever keeps using the window after
    /// the borrow ended must keep this value alive until it stopped.
    pub(crate) fn window_handle(&self) -> WindowHandle<'_> {
        let raw = RawWindowHandle::OhosNdk(OhosNdkWindowHandle::new(self.0));
        // SAFETY: The reference held by `self` keeps the window alive for the borrow.
        unsafe { WindowHandle::borrow_raw(raw) }
    }

    /// Tells the compositor that the CPU never reads the buffers of the window, which lets it
    /// pick a more efficient path. See
    /// <https://developer.huawei.com/consumer/en/doc/harmonyos-faqs/faqs-arkgraphics-2d-14>.
    pub(crate) fn disable_cpu_read(&self) {
        let window = self
            .0
            .as_ptr()
            .cast::<ohos_sys_opaque_types::NativeWindow>();
        let mut usage: u64 = 0;
        // SAFETY: The window is alive, and GET_USAGE writes a u64.
        let result = unsafe {
            OH_NativeWindow_NativeWindowHandleOpt(
                window,
                NativeWindowOperation::GET_USAGE as i32,
                &mut usage,
            )
        };
        if result != 0 {
            warn!("Getting the usage of a native window failed: {result}");
            return;
        }
        usage &= !(OH_NativeBuffer_Usage::NATIVEBUFFER_USAGE_CPU_READ.0 as u64);
        // SAFETY: The window is alive, and SET_USAGE reads a u64.
        let result = unsafe {
            OH_NativeWindow_NativeWindowHandleOpt(
                window,
                NativeWindowOperation::SET_USAGE as i32,
                usage,
            )
        };
        if result != 0 {
            warn!("Setting the usage of a native window failed: {result}");
        }
    }
}

impl Drop for NativeWindow {
    fn drop(&mut self) {
        // SAFETY: `self` holds a reference to the window, which this gives up.
        let result = unsafe { OH_NativeWindow_NativeObjectUnreference(self.0.as_ptr()) };
        if result != 0 {
            error!("Unreferencing a native window failed: {result}");
        }
    }
}

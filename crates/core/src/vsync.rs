/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

use std::cell::RefCell;
use std::ffi::{c_longlong, c_void};
use std::rc::Rc;

use log::error;
use ohos_vsync::NativeVsync;
use servo::RefreshDriver;

use crate::engine::{Action, WebViewId, send};

/// Drives the frames of one webview from the display vsync. Vsync callbacks are only requested
/// while Servo waits for a frame, so an idle page does not wake up the thread.
pub(crate) struct VsyncRefreshDriver {
    id: WebViewId,
    start_frame_callbacks: RefCell<Vec<Box<dyn Fn() + Send>>>,
    native_vsync: NativeVsync,
}

impl VsyncRefreshDriver {
    pub(crate) fn new(id: WebViewId) -> Option<Rc<Self>> {
        let native_vsync = NativeVsync::new(&format!("SkiffViewView{id}"))
            .inspect_err(|error| error!("Creating the vsync of webview {id} failed: {error:?}"))
            .ok()?;
        Some(Rc::new(Self {
            id,
            start_frame_callbacks: Default::default(),
            native_vsync,
        }))
    }

    pub(crate) fn notify_vsync(&self) {
        let callbacks: Vec<_> = self.start_frame_callbacks.borrow_mut().drain(..).collect();
        for callback in callbacks {
            callback();
        }
    }
}

impl RefreshDriver for VsyncRefreshDriver {
    fn observe_next_frame(&self, start_frame_callback: Box<dyn Fn() + Send + 'static>) {
        let was_empty = {
            let mut callbacks = self.start_frame_callbacks.borrow_mut();
            callbacks.push(start_frame_callback);
            callbacks.len() == 1
        };
        if !was_empty {
            return;
        }
        // SAFETY: `on_vsync` lives forever, and the data is the webview id, which is never
        // dereferenced, so the callback may outlive this driver.
        let result = unsafe {
            self.native_vsync
                .request_raw_callback(Some(on_vsync), self.id as usize as *mut c_void)
        };
        if let Err(error) = result {
            error!(
                "Requesting a vsync for webview {} failed: {error:?}",
                self.id
            );
        }
    }
}

/// Runs on the vsync thread of the system.
unsafe extern "C" fn on_vsync(_timestamp: c_longlong, data: *mut c_void) {
    let _ = send(Action::Vsync(data as usize as WebViewId));
}

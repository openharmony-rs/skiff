/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

use std::cell::Cell;
use std::rc::Rc;

use log::error;
use servo::{
    ConsoleLogLevel, EmbedderControl, EmbedderControlId, LoadStatus, SimpleDialog, WebView,
    WebViewDelegate,
};
use url::Url;

use crate::engine::{EventSink, WebViewEvent, WebViewId};
use crate::ime::SoftKeyboard;

pub(crate) struct Delegate {
    id: WebViewId,
    sink: EventSink,
    needs_repaint: Cell<bool>,
    keyboard: Rc<SoftKeyboard>,
    /// A load started, but is reported only once its URL is known. Servo reports the start before
    /// the URL of the webview changes, and the URL on another channel, which can lag behind.
    start_pending: Cell<bool>,
    /// The head of the page whose start is pending was parsed.
    head_parsed_pending: Cell<bool>,
}

impl Delegate {
    pub(crate) fn new(id: WebViewId, sink: EventSink, keyboard: Rc<SoftKeyboard>) -> Self {
        Self {
            id,
            sink,
            needs_repaint: Cell::new(false),
            keyboard,
            start_pending: Cell::new(false),
            head_parsed_pending: Cell::new(false),
        }
    }

    /// Reports the start of a load that Servo does not report, which are the first load of a
    /// webview and reloads.
    pub(crate) fn report_load_start(&self, url: String) {
        self.start_pending.set(false);
        self.head_parsed_pending.set(false);
        self.emit(WebViewEvent::LoadStarted(url));
        self.emit(WebViewEvent::Progress(10));
    }

    fn report_pending_start(&self, url: &str) {
        if self.start_pending.replace(false) {
            self.emit(WebViewEvent::LoadStarted(url.into()));
            self.emit(WebViewEvent::Progress(10));
            if self.head_parsed_pending.replace(false) {
                self.emit(WebViewEvent::Progress(60));
            }
        }
    }

    pub(crate) fn request_repaint(&self) {
        self.needs_repaint.set(true);
    }

    pub(crate) fn take_needs_repaint(&self) -> bool {
        self.needs_repaint.replace(false)
    }

    fn emit(&self, event: WebViewEvent) {
        (self.sink)(event);
    }
}

impl WebViewDelegate for Delegate {
    fn notify_url_changed(&self, _webview: WebView, url: Url) {
        let url = String::from(url);
        self.report_pending_start(&url);
        self.emit(WebViewEvent::UrlChanged(url));
    }

    fn notify_page_title_changed(&self, _webview: WebView, title: Option<String>) {
        self.emit(WebViewEvent::TitleChanged(title.unwrap_or_default()));
    }

    fn notify_load_status_changed(&self, webview: WebView, status: LoadStatus) {
        let url = webview.url().map(String::from).unwrap_or_default();
        match status {
            LoadStatus::Started => {
                self.start_pending.set(true);
                self.head_parsed_pending.set(false);
            },
            LoadStatus::HeadParsed if self.start_pending.get() => {
                self.head_parsed_pending.set(true);
            },
            LoadStatus::HeadParsed => self.emit(WebViewEvent::Progress(60)),
            LoadStatus::Complete => {
                self.report_pending_start(&url);
                self.emit(WebViewEvent::Progress(100));
                self.emit(WebViewEvent::LoadFinished(url));
            },
        }
    }

    fn notify_history_changed(&self, _webview: WebView, entries: Vec<Url>, current: usize) {
        self.emit(WebViewEvent::HistoryChanged {
            can_go_back: current > 0,
            can_go_forward: current + 1 < entries.len(),
        });
    }

    fn notify_new_frame_ready(&self, _webview: WebView) {
        self.request_repaint();
    }

    fn notify_crashed(&self, _webview: WebView, reason: String, backtrace: Option<String>) {
        error!(
            "Webview crashed: {reason}\n{}",
            backtrace.unwrap_or_default()
        );
        self.emit(WebViewEvent::Crashed(reason));
    }

    fn show_console_message(&self, _webview: WebView, level: ConsoleLogLevel, message: String) {
        let level = level.into();
        log::log!(level, "{message}");
        self.emit(WebViewEvent::ConsoleMessage { level, message });
    }

    fn show_embedder_control(&self, _webview: WebView, embedder_control: EmbedderControl) {
        let control_id = embedder_control.id();
        match embedder_control {
            EmbedderControl::InputMethod(control) if control.allow_virtual_keyboard() => {
                self.keyboard.show(self.id, control_id, &control);
            },
            EmbedderControl::SimpleDialog(SimpleDialog::Alert(alert)) => {
                self.emit(WebViewEvent::Alert(alert.message().into()));
                alert.confirm();
            },
            // Dropping the control sends the default response.
            _ => {},
        }
    }

    fn hide_embedder_control(&self, _webview: WebView, control_id: EmbedderControlId) {
        self.keyboard.hide(self.id, control_id);
    }
}

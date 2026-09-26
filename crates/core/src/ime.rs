/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

use std::cell::{Cell, RefCell};
use std::sync::atomic::{AtomicU32, Ordering};

use log::{debug, error};
use ohos_ime::{AttachOptions, Ime, ImeProxy, KeyboardStatus, RawTextEditorProxy, TextConfig};
use ohos_ime_sys::types::{InputMethod_EnterKeyType, InputMethod_TextInputType};
use servo::{
    CompositionEvent, CompositionState, EmbedderControlId, ImeEvent, InputEvent,
    InputMethodControl, InputMethodType, Key, KeyState, KeyboardEvent, NamedKey, WebView,
};

use crate::engine::{Action, WebViewId, send};

/// Input from the soft keyboard, delivered on the Servo thread.
pub(crate) enum ImeInput {
    InsertText(String),
    DeleteForward(usize),
    DeleteBackward(usize),
    Enter,
    Dismissed,
}

/// The webview whose session has the soft keyboard, or 0, readable from any thread.
static KEYBOARD_OWNER: AtomicU32 = AtomicU32::new(0);

/// Whether the webview has the soft keyboard.
pub(crate) fn has_keyboard(webview_id: WebViewId) -> bool {
    webview_id != 0 && KEYBOARD_OWNER.load(Ordering::Relaxed) == webview_id
}

/// The soft keyboard. The system gives a process a single input session, and closing it closes
/// whatever uses it at that moment, including ArkUI text fields, so all webviews share this.
#[derive(Default)]
pub(crate) struct SoftKeyboard {
    session: RefCell<Option<Session>>,
    last_session_id: Cell<u64>,
}

/// The input session of an editable element in a webview.
struct Session {
    id: u64,
    webview_id: WebViewId,
    control_id: EmbedderControlId,
    multiline: bool,
    /// Dropping it closes the input session.
    proxy: ImeProxy,
}

impl SoftKeyboard {
    pub(crate) fn show(
        &self,
        webview_id: WebViewId,
        control_id: EmbedderControlId,
        control: &InputMethodControl,
    ) {
        let mut session = self.session.borrow_mut();
        let current = session.as_ref().is_some_and(|session| {
            session.webview_id == webview_id && session.control_id == control_id
        });
        if !current {
            // Drop the old session before attaching, which replaces the input session anyway.
            *session = None;
            KEYBOARD_OWNER.store(0, Ordering::Relaxed);
            let id = self.last_session_id.get() + 1;
            self.last_session_id.set(id);
            let editor = TextEditor {
                session_id: id,
                text_config: text_config(control.input_method_type(), control.multiline()),
            };
            let proxy = RawTextEditorProxy::new(Box::new(editor))
                .map_err(|error| format!("{error:?}"))
                .and_then(|editor| {
                    ImeProxy::new(editor, AttachOptions::new(true))
                        .map_err(|error| format!("{error:?}"))
                });
            match proxy {
                Ok(proxy) => {
                    *session = Some(Session {
                        id,
                        webview_id,
                        control_id,
                        multiline: control.multiline(),
                        proxy,
                    });
                    KEYBOARD_OWNER.store(webview_id, Ordering::Relaxed);
                },
                Err(error) => {
                    error!("Attaching the soft keyboard failed: {error}");
                    return;
                },
            }
        }
        if let Some(session) = session.as_ref() &&
            session.proxy.show_keyboard().is_err()
        {
            error!("Showing the soft keyboard failed");
        }
    }

    /// Closes the session of the given element, if it still has the soft keyboard.
    pub(crate) fn hide(&self, webview_id: WebViewId, control_id: EmbedderControlId) {
        let has_keyboard = self.session.borrow().as_ref().is_some_and(|session| {
            session.webview_id == webview_id && session.control_id == control_id
        });
        if has_keyboard {
            self.close();
        }
    }

    /// Closes the session of the webview, if it has the soft keyboard, and returns whether it had.
    pub(crate) fn release(&self, webview_id: WebViewId) -> bool {
        let has_keyboard = self
            .session
            .borrow()
            .as_ref()
            .is_some_and(|session| session.webview_id == webview_id);
        if has_keyboard {
            self.close();
        }
        has_keyboard
    }

    /// Returns the webview whose session had the id, if that session is still open.
    pub(crate) fn owner(&self, session_id: u64) -> Option<WebViewId> {
        self.session
            .borrow()
            .as_ref()
            .filter(|session| session.id == session_id)
            .map(|session| session.webview_id)
    }

    pub(crate) fn dismiss(&self, webview: &WebView) {
        self.close();
        webview.notify_input_event(InputEvent::Ime(ImeEvent::Dismissed));
    }

    fn close(&self) {
        let session = self.session.take();
        KEYBOARD_OWNER.store(0, Ordering::Relaxed);
        if let Some(session) = session &&
            session.proxy.hide_keyboard().is_err()
        {
            error!("Hiding the soft keyboard failed");
        }
    }

    /// Delivers input of the open session to its webview.
    pub(crate) fn handle_input(&self, webview: &WebView, input: ImeInput) {
        match input {
            // The system sends an empty text after the intended one.
            ImeInput::InsertText(text) if text.is_empty() => {},
            ImeInput::InsertText(text) => {
                webview.notify_input_event(InputEvent::Keyboard(
                    KeyboardEvent::from_state_and_key(
                        KeyState::Down,
                        Key::Named(NamedKey::Process),
                    ),
                ));
                webview.notify_input_event(InputEvent::Ime(ImeEvent::Composition(
                    CompositionEvent {
                        state: CompositionState::End,
                        data: text,
                    },
                )));
                webview.notify_input_event(InputEvent::Keyboard(
                    KeyboardEvent::from_state_and_key(KeyState::Up, Key::Named(NamedKey::Process)),
                ));
            },
            ImeInput::DeleteForward(count) => press(webview, NamedKey::Delete, count),
            ImeInput::DeleteBackward(count) => press(webview, NamedKey::Backspace, count),
            ImeInput::Enter => {
                press(webview, NamedKey::Enter, 1);
                // Enter ends the input of single line fields, like in ArkUI's text fields.
                let multiline = self
                    .session
                    .borrow()
                    .as_ref()
                    .is_some_and(|session| session.multiline);
                if !multiline {
                    self.dismiss(webview);
                }
            },
            ImeInput::Dismissed => self.dismiss(webview),
        }
    }
}

fn press(webview: &WebView, key: NamedKey, count: usize) {
    for _ in 0..count {
        for state in [KeyState::Down, KeyState::Up] {
            webview.notify_input_event(InputEvent::Keyboard(KeyboardEvent::from_state_and_key(
                state,
                Key::Named(key),
            )));
        }
    }
}

/// Receives the input of the soft keyboard on a system thread.
struct TextEditor {
    session_id: u64,
    text_config: TextConfig,
}

impl TextEditor {
    fn send(&self, input: ImeInput) {
        let _ = send(Action::Ime {
            session_id: self.session_id,
            input,
        });
    }
}

impl Ime for TextEditor {
    fn insert_text(&self, text: String) {
        self.send(ImeInput::InsertText(text));
    }

    fn delete_forward(&self, len: usize) {
        self.send(ImeInput::DeleteForward(len));
    }

    fn delete_backward(&self, len: usize) {
        self.send(ImeInput::DeleteBackward(len));
    }

    fn get_text_config(&self) -> &TextConfig {
        &self.text_config
    }

    fn send_enter_key(&self, _enter_key: InputMethod_EnterKeyType) {
        self.send(ImeInput::Enter);
    }

    fn keyboard_status_changed(&self, status: KeyboardStatus) {
        debug!("Soft keyboard status changed to {status:?}");
        if matches!(status, KeyboardStatus::Hidden) {
            self.send(ImeInput::Dismissed);
        }
    }
}

fn text_config(input_method_type: InputMethodType, multiline: bool) -> TextConfig {
    use InputMethod_TextInputType as TextInputType;
    let input_type = match input_method_type {
        InputMethodType::DatetimeLocal => TextInputType::IME_TEXT_INPUT_TYPE_DATETIME,
        InputMethodType::Email => TextInputType::IME_TEXT_INPUT_TYPE_EMAIL_ADDRESS,
        InputMethodType::Number => TextInputType::IME_TEXT_INPUT_TYPE_NUMBER,
        InputMethodType::Password => TextInputType::IME_TEXT_INPUT_TYPE_NEW_PASSWORD,
        InputMethodType::Tel => TextInputType::IME_TEXT_INPUT_TYPE_PHONE,
        InputMethodType::Text if multiline => TextInputType::IME_TEXT_INPUT_TYPE_MULTILINE,
        InputMethodType::Url => TextInputType::IME_TEXT_INPUT_TYPE_URL,
        _ => TextInputType::IME_TEXT_INPUT_TYPE_TEXT,
    };
    let enterkey_type = match (input_method_type, multiline) {
        (InputMethodType::Text, true) => InputMethod_EnterKeyType::IME_ENTER_KEY_NEWLINE,
        (InputMethodType::Text, false) => InputMethod_EnterKeyType::IME_ENTER_KEY_DONE,
        (InputMethodType::Search, false) => InputMethod_EnterKeyType::IME_ENTER_KEY_SEARCH,
        _ => InputMethod_EnterKeyType::IME_ENTER_KEY_UNSPECIFIED,
    };
    ohos_ime::TextConfigBuilder::new()
        .input_type(input_type)
        .enterkey_type(enterkey_type)
        .build()
}

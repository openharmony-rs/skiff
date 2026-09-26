/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

use std::any::Any;
use std::collections::HashMap;
use std::mem::ManuallyDrop;
use std::panic::{self, AssertUnwindSafe};
use std::path::PathBuf;
use std::rc::Rc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::{Arc, LazyLock, Mutex, MutexGuard, OnceLock, PoisonError};
use std::thread;
use std::time::Duration;

use dpi::PhysicalSize;
use euclid::Scale;
use log::{debug, error, info, warn};
use raw_window_handle::{DisplayHandle, OhosDisplayHandle, RawDisplayHandle};
use servo::protocol_handler::ProtocolRegistry;
use servo::{
    DeviceIndependentPixel, DevicePixel, DevicePoint, EventLoopWaker, ImeEvent, InputEvent,
    JSValue, KeyboardEvent, Opts, PrefValue, Preferences, RenderingContext, Servo, ServoBuilder,
    TouchEvent, TouchEventType, TouchId, TouchPointerType, WebView, WebViewBuilder,
    WindowRenderingContext,
};
use url::Url;

use crate::delegate::Delegate;
use crate::ime::{self, ImeInput, SoftKeyboard};
use crate::native_window::NativeWindow;
use crate::preferences::check_preference;
use crate::protocol::ServoProtocolHandler;
use crate::vsync::VsyncRefreshDriver;

/// How long the system thread waits for Servo to stop using a surface that is about to go away.
/// Servo might in turn wait for the system thread, so this can't wait forever.
const SURFACE_TIMEOUT: Duration = Duration::from_millis(500);
const SHUTDOWN_TIMEOUT: Duration = Duration::from_secs(5);

/// Identifies a webview. Chosen by the caller of [`create_webview`].
pub type WebViewId = u32;

/// Receives the events of one webview. Called on the Servo thread, except for
/// [`WebViewEvent::EngineStopped`].
pub type EventSink = Arc<dyn Fn(WebViewEvent) + Send + Sync>;

/// Receives the result of [`evaluate_javascript`] as JSON, or an error message.
pub type JavaScriptCallback = Box<dyn FnOnce(Result<String, String>) + Send>;

pub struct EngineOptions {
    /// Directory for Servo's configuration and site data.
    pub config_dir: PathBuf,
    pub preferences: Preferences,
    /// Device pixels per CSS pixel.
    pub hidpi_scale_factor: f32,
}

#[derive(Debug)]
pub enum WebViewEvent {
    UrlChanged(String),
    TitleChanged(String),
    LoadStarted(String),
    LoadFinished(String),
    /// Load progress in percent. Servo only reports a few steps.
    Progress(u32),
    HistoryChanged {
        can_go_back: bool,
        can_go_forward: bool,
    },
    ConsoleMessage {
        level: log::Level,
        message: String,
    },
    /// The page called `alert()`. It continues without waiting.
    Alert(String),
    /// The page crashed.
    Crashed(String),
    /// Servo stopped, because it was shut down or crashed. The webview can't be used anymore.
    EngineStopped(String),
}

#[derive(Clone, Copy, Debug)]
pub enum TouchPhase {
    Down,
    Move,
    Up,
    Cancel,
}

pub(crate) enum Action {
    WakeUp,
    Vsync(WebViewId),
    Create {
        id: WebViewId,
        url: Option<String>,
        sink: EventSink,
    },
    Destroy(WebViewId),
    AttachSurface {
        id: WebViewId,
        window: NativeWindow,
        size: PhysicalSize<u32>,
    },
    ResizeSurface {
        id: WebViewId,
        size: PhysicalSize<u32>,
    },
    DetachSurface {
        id: WebViewId,
        done: Sender<()>,
    },
    SetSurfaceVisible {
        id: WebViewId,
        visible: bool,
    },
    SetVisible {
        id: WebViewId,
        visible: bool,
    },
    SetAppVisible(bool),
    Blur {
        id: WebViewId,
        done: Sender<()>,
    },
    DismissKeyboard(WebViewId),
    SetPreference {
        name: String,
        value: PrefValue,
        done: Sender<()>,
    },
    LoadUrl {
        id: WebViewId,
        url: String,
    },
    Reload(WebViewId),
    GoBack(WebViewId),
    GoForward(WebViewId),
    EvaluateJavaScript {
        id: WebViewId,
        script: String,
        pending: PendingScript,
    },
    Touch {
        id: WebViewId,
        phase: TouchPhase,
        pointer_id: i32,
        x: f32,
        y: f32,
    },
    Key {
        id: WebViewId,
        event: keyboard_types::KeyboardEvent,
    },
    Ime {
        session_id: u64,
        input: ImeInput,
    },
    Shutdown(Sender<()>),
}

static SENDER: OnceLock<Sender<Action>> = OnceLock::new();

/// The event sinks of all webviews, to tell them when Servo stops.
static SINKS: LazyLock<Mutex<HashMap<WebViewId, EventSink>>> = LazyLock::new(Default::default);

/// The callbacks of scripts that did not finish yet, to fail them when Servo stops.
static PENDING_SCRIPTS: LazyLock<Mutex<HashMap<u64, JavaScriptCallback>>> =
    LazyLock::new(Default::default);
static NEXT_SCRIPT_ID: AtomicU64 = AtomicU64::new(1);

fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex.lock().unwrap_or_else(PoisonError::into_inner)
}

/// Starts the Servo thread. Returns false if it was already started.
pub fn start(options: EngineOptions) -> bool {
    let (sender, receiver) = mpsc::channel();
    if SENDER.set(sender.clone()).is_err() {
        return false;
    }
    thread::Builder::new()
        .name("Servo".into())
        .spawn(move || run_servo_thread(options, sender, receiver))
        .expect("Could not spawn the Servo thread");
    true
}

/// Shuts Servo down, which saves cookies and other site data, and waits for it to finish, but at
/// most 5 s. Servo can't be started again afterwards.
pub fn shutdown() {
    let (done, receiver) = mpsc::channel();
    if send(Action::Shutdown(done)).is_ok() && receiver.recv_timeout(SHUTDOWN_TIMEOUT).is_err() {
        warn!("Servo did not shut down in time");
    }
}

/// Sends an action to the Servo thread, and returns it if the thread is not running.
pub(crate) fn send(action: Action) -> Result<(), Action> {
    let Some(sender) = SENDER.get() else {
        return Err(action);
    };
    sender.send(action).map_err(|error| error.0)
}

/// Creates a webview, which loads `url` once it gets a surface. If Servo is not running, `sink`
/// receives [`WebViewEvent::EngineStopped`].
pub fn create_webview(id: WebViewId, url: Option<String>, sink: EventSink) {
    lock(&SINKS).insert(id, sink.clone());
    let action = Action::Create {
        id,
        url,
        sink: sink.clone(),
    };
    if send(action).is_err() {
        lock(&SINKS).remove(&id);
        sink(WebViewEvent::EngineStopped("Servo is not running".into()));
    }
}

pub fn destroy_webview(id: WebViewId) {
    lock(&SINKS).remove(&id);
    let _ = send(Action::Destroy(id));
}

/// Makes the webview render into `window`, which is `size` device pixels large.
pub fn attach_surface(id: WebViewId, window: NativeWindow, size: PhysicalSize<u32>) {
    let _ = send(Action::AttachSurface { id, window, size });
}

pub fn resize_surface(id: WebViewId, size: PhysicalSize<u32>) {
    let _ = send(Action::ResizeSurface { id, size });
}

/// Makes the webview stop using its surface, which is about to be destroyed, and waits for it.
pub fn detach_surface(id: WebViewId) {
    let (done, receiver) = mpsc::channel();
    if send(Action::DetachSurface { id, done }).is_ok() &&
        receiver.recv_timeout(SURFACE_TIMEOUT).is_err()
    {
        warn!("Servo might still use the destroyed surface of webview {id}");
    }
}

/// Tells whether the system shows the surface of the webview, which it doesn't while the app is in
/// the background. Webviews are hidden and throttled while their surface is not shown.
pub fn set_surface_visible(id: WebViewId, visible: bool) {
    let _ = send(Action::SetSurfaceVisible { id, visible });
}

/// Shows or hides the webview. Hidden webviews are throttled.
pub fn set_visible(id: WebViewId, visible: bool) {
    let _ = send(Action::SetVisible { id, visible });
}

/// Tells whether the app is in the foreground. All webviews are hidden and throttled while it is
/// in the background.
pub fn set_app_visible(visible: bool) {
    let _ = send(Action::SetAppVisible(visible));
}

/// Takes the focus away from the page, because another component got it, and waits until the
/// webview released the soft keyboard, so that the other component can use it.
pub fn blur(id: WebViewId) {
    let (done, receiver) = mpsc::channel();
    if send(Action::Blur { id, done }).is_ok() && receiver.recv_timeout(SURFACE_TIMEOUT).is_err() {
        warn!("Webview {id} might still have the soft keyboard");
    }
}

/// Changes a preference of the running Servo. Pages that load afterwards use the new value, unless
/// the preference is one that Servo only reads when it starts.
pub fn set_preference(name: &str, value: PrefValue) -> Result<(), String> {
    let value = check_preference(name, value)?;
    let (done, receiver) = mpsc::channel();
    let action = Action::SetPreference {
        name: name.into(),
        value,
        done,
    };
    if send(action).is_err() {
        return Err("Servo is not running".into());
    }
    if receiver.recv_timeout(SURFACE_TIMEOUT).is_err() {
        warn!("Servo might not have changed preference {name} yet");
    }
    Ok(())
}

/// Closes the soft keyboard if the webview has it, e.g. because the user went back, and returns
/// whether it had.
pub fn dismiss_soft_keyboard(id: WebViewId) -> bool {
    if !ime::has_keyboard(id) {
        return false;
    }
    let _ = send(Action::DismissKeyboard(id));
    true
}

pub fn load_url(id: WebViewId, url: String) {
    let _ = send(Action::LoadUrl { id, url });
}

pub fn reload(id: WebViewId) {
    let _ = send(Action::Reload(id));
}

pub fn go_back(id: WebViewId) {
    let _ = send(Action::GoBack(id));
}

pub fn go_forward(id: WebViewId) {
    let _ = send(Action::GoForward(id));
}

/// Runs `script` in the page. `callback` is called exactly once, also if the webview or Servo goes
/// away first.
pub fn evaluate_javascript(id: WebViewId, script: String, callback: JavaScriptCallback) {
    let pending = PendingScript::new(callback);
    // If sending fails, dropping the action fails the script.
    let _ = send(Action::EvaluateJavaScript {
        id,
        script,
        pending,
    });
}

/// A touch at `x`, `y` in device pixels relative to the surface.
pub fn touch_event(id: WebViewId, phase: TouchPhase, pointer_id: i32, x: f32, y: f32) {
    let _ = send(Action::Touch {
        id,
        phase,
        pointer_id,
        x,
        y,
    });
}

pub fn key_event(id: WebViewId, event: keyboard_types::KeyboardEvent) {
    let _ = send(Action::Key { id, event });
}

/// A script whose callback has not been called yet. Dropping it calls the callback with an error.
pub(crate) struct PendingScript(u64);

impl PendingScript {
    fn new(callback: JavaScriptCallback) -> Self {
        let id = NEXT_SCRIPT_ID.fetch_add(1, Ordering::Relaxed);
        lock(&PENDING_SCRIPTS).insert(id, callback);
        Self(id)
    }

    fn finish(self, result: Result<String, String>) {
        let callback = lock(&PENDING_SCRIPTS).remove(&self.0);
        if let Some(callback) = callback {
            callback(result);
        }
    }
}

impl Drop for PendingScript {
    fn drop(&mut self) {
        let callback = lock(&PENDING_SCRIPTS).remove(&self.0);
        if let Some(callback) = callback {
            callback(Err("The script was dropped before it finished".into()));
        }
    }
}

fn run_servo_thread(options: EngineOptions, sender: Sender<Action>, receiver: Receiver<Action>) {
    let result = panic::catch_unwind(AssertUnwindSafe(|| {
        // Not dropped when Servo panics, since shutting it down then might hang or panic again.
        let mut thread = ManuallyDrop::new(ServoThread::new(options, sender));
        let done = thread.run(&receiver);
        drop(ManuallyDrop::into_inner(thread));
        done
    }));
    // From now on, sending actions fails.
    drop(receiver);
    let (reason, done) = match result {
        Ok(done) => {
            info!("Servo was shut down");
            ("Servo was shut down".to_owned(), Some(done))
        },
        Err(payload) => {
            let reason = format!("Servo crashed: {}", panic_message(&*payload));
            error!("{reason}");
            (reason, None)
        },
    };
    let sinks: Vec<_> = lock(&SINKS).drain().map(|(_, sink)| sink).collect();
    for sink in sinks {
        sink(WebViewEvent::EngineStopped(reason.clone()));
    }
    let callbacks: Vec<_> = lock(&PENDING_SCRIPTS)
        .drain()
        .map(|(_, callback)| callback)
        .collect();
    for callback in callbacks {
        callback(Err(reason.clone()));
    }
    if let Some(done) = done {
        let _ = done.send(());
    }
}

fn panic_message(payload: &(dyn Any + Send)) -> &str {
    payload
        .downcast_ref::<&str>()
        .copied()
        .or_else(|| payload.downcast_ref::<String>().map(String::as_str))
        .unwrap_or("unknown panic")
}

#[derive(Clone)]
struct Waker(Sender<Action>);

impl EventLoopWaker for Waker {
    fn clone_box(&self) -> Box<dyn EventLoopWaker> {
        Box::new(self.clone())
    }

    fn wake(&self) {
        let _ = self.0.send(Action::WakeUp);
    }
}

struct Entry {
    /// Moved into the delegate when the webview is built.
    sink: Option<EventSink>,
    /// A URL to load as soon as the webview can navigate.
    pending_url: Option<Url>,
    /// Whether the app shows the webview.
    visible: bool,
    /// Whether the system shows the surface.
    surface_visible: bool,
    size: PhysicalSize<u32>,
    /// Built once the webview has a surface with a real size. Declared before `surface`, so that
    /// it stops using the surface before the reference to the surface is dropped.
    built: Option<BuiltWebView>,
    surface: Option<NativeWindow>,
}

struct BuiltWebView {
    webview: WebView,
    delegate: Rc<Delegate>,
    rendering_context: Rc<WindowRenderingContext>,
    refresh_driver: Rc<VsyncRefreshDriver>,
    visible: bool,
}

struct ServoThread {
    /// Declared before `servo`, so that the webviews are gone when Servo shuts down.
    webviews: HashMap<WebViewId, Entry>,
    keyboard: Rc<SoftKeyboard>,
    hidpi_scale_factor: Scale<f32, DeviceIndependentPixel, DevicePixel>,
    /// Whether the app is in the foreground.
    app_visible: bool,
    servo: Servo,
}

impl ServoThread {
    fn new(options: EngineOptions, sender: Sender<Action>) -> Self {
        if rustls::crypto::aws_lc_rs::default_provider()
            .install_default()
            .is_err()
        {
            info!("A rustls crypto provider was already installed");
        }
        let opts = Opts {
            config_dir: Some(options.config_dir),
            ..Default::default()
        };
        let mut protocols = ProtocolRegistry::default();
        if let Err(error) = protocols.register("servo", ServoProtocolHandler) {
            error!("Registering the servo: URLs failed: {error:?}");
        }
        let servo = ServoBuilder::default()
            .opts(opts)
            .preferences(options.preferences)
            .protocol_registry(protocols)
            .event_loop_waker(Box::new(Waker(sender)))
            .build();
        Self {
            webviews: HashMap::new(),
            keyboard: Default::default(),
            hidpi_scale_factor: Scale::new(options.hidpi_scale_factor),
            app_visible: true,
            servo,
        }
    }

    /// Handles actions until Servo is shut down, and returns who waits for that.
    fn run(&mut self, receiver: &Receiver<Action>) -> Sender<()> {
        loop {
            let mut next = receiver.recv().ok();
            while let Some(action) = next {
                if let Action::Shutdown(done) = action {
                    self.webviews.clear();
                    return done;
                }
                self.handle(action);
                next = receiver.try_recv().ok();
            }
            self.servo.spin_event_loop();
            self.load_pending_urls();
            self.repaint();
        }
    }

    fn built(&self, id: WebViewId) -> Option<&BuiltWebView> {
        self.webviews.get(&id)?.built.as_ref()
    }

    fn with_webview(&self, id: WebViewId, callback: impl FnOnce(&WebView)) {
        if let Some(built) = self.built(id) {
            callback(&built.webview);
        }
    }

    fn handle(&mut self, action: Action) {
        match action {
            Action::WakeUp => {},
            Action::Vsync(id) => {
                if let Some(built) = self.built(id) {
                    built.refresh_driver.notify_vsync();
                }
            },
            Action::Create { id, url, sink } => {
                let entry = Entry {
                    sink: Some(sink),
                    pending_url: url.as_deref().and_then(parse_url),
                    visible: true,
                    surface_visible: true,
                    size: PhysicalSize::new(0, 0),
                    built: None,
                    surface: None,
                };
                if self.webviews.insert(id, entry).is_some() {
                    error!("Replaced the existing webview {id}");
                }
            },
            Action::Destroy(id) => {
                let _ = self.keyboard.release(id);
                self.webviews.remove(&id);
            },
            Action::AttachSurface { id, window, size } => self.attach_surface(id, window, size),
            Action::ResizeSurface { id, size } => {
                let Some(entry) = self.webviews.get_mut(&id) else {
                    return;
                };
                entry.size = size;
                match &entry.built {
                    Some(built) if entry.surface.is_some() => built.webview.resize(size),
                    Some(_) => {},
                    None => self.build_webview(id),
                }
            },
            Action::DetachSurface { id, done } => {
                if let Some(entry) = self.webviews.get_mut(&id) {
                    detach_surface_of(entry);
                }
                let _ = done.send(());
            },
            Action::SetSurfaceVisible { id, visible } => {
                if let Some(entry) = self.webviews.get_mut(&id) {
                    entry.surface_visible = visible;
                    apply_visibility(id, entry, self.app_visible);
                }
            },
            Action::SetVisible { id, visible } => {
                if let Some(entry) = self.webviews.get_mut(&id) {
                    entry.visible = visible;
                    apply_visibility(id, entry, self.app_visible);
                }
            },
            Action::SetAppVisible(visible) => {
                self.app_visible = visible;
                for (id, entry) in &mut self.webviews {
                    apply_visibility(*id, entry, visible);
                }
            },
            Action::Blur { id, done } => {
                let had_keyboard = self.keyboard.release(id);
                self.with_webview(id, |webview| {
                    // Blurs the edited element, so that touching it again shows the soft keyboard.
                    if had_keyboard {
                        webview.notify_input_event(InputEvent::Ime(ImeEvent::Dismissed));
                    }
                    webview.blur();
                });
                let _ = done.send(());
            },
            Action::DismissKeyboard(id) => {
                if ime::has_keyboard(id) &&
                    let Some(built) = self.built(id)
                {
                    self.keyboard.dismiss(&built.webview);
                }
            },
            Action::SetPreference { name, value, done } => {
                self.servo.set_preference(&name, value);
                let _ = done.send(());
            },
            Action::LoadUrl { id, url } => {
                if let Some(entry) = self.webviews.get_mut(&id) &&
                    let Some(url) = parse_url(&url)
                {
                    entry.pending_url = Some(url);
                }
            },
            Action::Reload(id) => {
                if let Some(built) = self.built(id) {
                    let url = built.webview.url().map(String::from).unwrap_or_default();
                    built.delegate.report_load_start(url);
                    built.webview.reload();
                }
            },
            Action::GoBack(id) => self.with_webview(id, |webview| {
                webview.go_back(1);
            }),
            Action::GoForward(id) => self.with_webview(id, |webview| {
                webview.go_forward(1);
            }),
            Action::EvaluateJavaScript {
                id,
                script,
                pending,
            } => match self.built(id) {
                Some(built) => built.webview.evaluate_javascript(script, move |result| {
                    pending.finish(
                        result
                            .map(|value| js_value_to_json(&value).to_string())
                            .map_err(|error| format!("{error:?}")),
                    )
                }),
                None => pending.finish(Err(format!("Webview {id} is not ready"))),
            },
            Action::Touch {
                id,
                phase,
                pointer_id,
                x,
                y,
            } => self.with_webview(id, |webview| {
                if matches!(phase, TouchPhase::Down) && !webview.focused() {
                    webview.focus();
                }
                let event_type = match phase {
                    TouchPhase::Down => TouchEventType::Down,
                    TouchPhase::Move => TouchEventType::Move,
                    TouchPhase::Up => TouchEventType::Up,
                    TouchPhase::Cancel => TouchEventType::Cancel,
                };
                webview.notify_input_event(InputEvent::Touch(TouchEvent::new(
                    event_type,
                    TouchId(pointer_id),
                    DevicePoint::new(x, y).into(),
                    TouchPointerType::Touch,
                )));
            }),
            Action::Key { id, event } => self.with_webview(id, |webview| {
                webview.notify_input_event(InputEvent::Keyboard(KeyboardEvent::new(event)));
            }),
            Action::Ime { session_id, input } => {
                // Input of a session that was closed in the meantime is dropped.
                if let Some(id) = self.keyboard.owner(session_id) &&
                    let Some(built) = self.built(id)
                {
                    self.keyboard.handle_input(&built.webview, input);
                }
            },
            // Handled by `run`.
            Action::Shutdown(_) => {},
        }
    }

    fn attach_surface(&mut self, id: WebViewId, window: NativeWindow, size: PhysicalSize<u32>) {
        let Some(entry) = self.webviews.get_mut(&id) else {
            warn!("Surface for unknown webview {id}");
            return;
        };
        detach_surface_of(entry);
        window.disable_cpu_read();
        entry.size = size;
        let Some(built) = &entry.built else {
            entry.surface = Some(window);
            self.build_webview(id);
            return;
        };
        if let Err(error) = built
            .rendering_context
            .set_window(window.window_handle(), size)
        {
            error!("Binding the surface of webview {id} failed: {error:?}");
            return;
        }
        // `set_window` keeps the size of the rendering context, so this updates it and the
        // viewport of the page.
        built.webview.resize(size);
        built.delegate.request_repaint();
        entry.surface = Some(window);
    }

    /// Builds the webview once it has a surface with a real size.
    fn build_webview(&mut self, id: WebViewId) {
        let Some(entry) = self.webviews.get_mut(&id) else {
            return;
        };
        let Some(window) = &entry.surface else {
            return;
        };
        if entry.built.is_some() || entry.size.width <= 1 || entry.size.height <= 1 {
            return;
        }
        let Some(refresh_driver) = VsyncRefreshDriver::new(id) else {
            return;
        };
        // SAFETY: OpenHarmony has a single display, which lives as long as the process.
        let display_handle =
            unsafe { DisplayHandle::borrow_raw(RawDisplayHandle::Ohos(OhosDisplayHandle::new())) };
        let rendering_context = match WindowRenderingContext::new_with_refresh_driver(
            display_handle,
            window.window_handle(),
            entry.size,
            refresh_driver.clone(),
        ) {
            Ok(rendering_context) => Rc::new(rendering_context),
            Err(error) => {
                error!("Creating the rendering context of webview {id} failed: {error:?}");
                return;
            },
        };
        let Some(sink) = entry.sink.take() else {
            return;
        };
        let delegate = Rc::new(Delegate::new(id, sink, self.keyboard.clone()));
        let mut builder = WebViewBuilder::new(&self.servo, rendering_context.clone())
            .delegate(delegate.clone())
            .hidpi_scale_factor(self.hidpi_scale_factor);
        if let Some(url) = entry.pending_url.take() {
            delegate.report_load_start(url.to_string());
            builder = builder.url(url);
        }
        let webview = builder.build();
        webview.show();
        webview.focus();
        info!(
            "Built webview {id} at {}x{}",
            entry.size.width, entry.size.height
        );
        entry.built = Some(BuiltWebView {
            webview,
            delegate,
            rendering_context,
            refresh_driver,
            visible: true,
        });
        apply_visibility(id, entry, self.app_visible);
    }

    /// Loads the URLs requested since the last turn. Servo drops a load until the constellation
    /// knows the webview, which is when the webview has a URL.
    fn load_pending_urls(&mut self) {
        for entry in self.webviews.values_mut() {
            if let Some(built) = &entry.built &&
                built.webview.url().is_some() &&
                let Some(url) = entry.pending_url.take()
            {
                built.webview.load(url);
            }
        }
    }

    fn repaint(&self) {
        for entry in self.webviews.values() {
            let Some(built) = &entry.built else {
                continue;
            };
            if entry.surface.is_none() || !built.visible || !built.delegate.take_needs_repaint() {
                continue;
            }
            if let Err(error) = built.rendering_context.make_current() {
                error!("Making the rendering context current failed: {error:?}");
                continue;
            }
            built.webview.paint();
            built.rendering_context.present();
        }
    }
}

/// Makes the webview stop using its surface and drops the reference to it.
fn detach_surface_of(entry: &mut Entry) {
    let Some(window) = entry.surface.take() else {
        return;
    };
    if let Some(built) = &entry.built {
        if let Err(error) = built.rendering_context.take_window() {
            warn!("Unbinding the surface from the rendering context failed: {error:?}");
        }
        // Unbinding makes the previously current surface current again, which might be the one
        // about to be destroyed. EGL only releases it once it isn't current anymore.
        if let Err(error) = built.rendering_context.make_current() {
            warn!("Making the rendering context current without a surface failed: {error:?}");
        }
    }
    drop(window);
}

/// Shows and unthrottles the webview if the app is in the foreground and both the app and the
/// system show the webview, and otherwise hides and throttles it.
fn apply_visibility(id: WebViewId, entry: &mut Entry, app_visible: bool) {
    let visible = app_visible && entry.visible && entry.surface_visible;
    let Some(built) = &mut entry.built else {
        return;
    };
    if built.visible == visible {
        return;
    }
    debug!(
        "Webview {id} is {}",
        if visible { "visible" } else { "hidden" }
    );
    built.visible = visible;
    if visible {
        built.webview.show();
    } else {
        built.webview.hide();
    }
    built.webview.set_throttled(!visible);
}

fn parse_url(url: &str) -> Option<Url> {
    Url::parse(url)
        .inspect_err(|error| error!("Not loading the invalid URL {url:?}: {error}"))
        .ok()
}

fn js_value_to_json(value: &JSValue) -> serde_json::Value {
    use serde_json::Value;
    match value {
        JSValue::Undefined | JSValue::Null => Value::Null,
        JSValue::Boolean(boolean) => Value::Bool(*boolean),
        JSValue::Number(number) if number.fract() == 0.0 && number.abs() < 2f64.powi(53) => {
            Value::from(*number as i64)
        },
        JSValue::Number(number) => Value::from(*number),
        JSValue::String(string) |
        JSValue::Element(string) |
        JSValue::ShadowRoot(string) |
        JSValue::Frame(string) |
        JSValue::Window(string) => Value::String(string.clone()),
        JSValue::Array(values) => Value::Array(values.iter().map(js_value_to_json).collect()),
        JSValue::Object(object) => Value::Object(
            object
                .iter()
                .map(|(key, value)| (key.clone(), js_value_to_json(value)))
                .collect(),
        ),
    }
}

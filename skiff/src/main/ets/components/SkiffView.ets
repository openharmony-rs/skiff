/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import hilog from '@ohos.hilog';
import skiff, { WebViewEvent } from 'libskiff.so';
import { SkiffRuntime } from './SkiffRuntime';
import { SkiffController } from './SkiffController';

export interface OnPageBeginEvent {
  url: string;
}

export interface OnPageEndEvent {
  url: string;
}

export interface OnProgressChangeEvent {
  newProgress: number;
}

export interface OnTitleReceiveEvent {
  title: string;
}

export interface OnUrlChangeEvent {
  url: string;
}

export interface OnHistoryChangeEvent {
  canGoBack: boolean;
  canGoForward: boolean;
}

export interface OnConsoleEvent {
  /** One of `error`, `warn`, `info`, `debug` and `trace`. */
  level: string;
  message: string;
}

export interface OnAlertEvent {
  message: string;
}

export interface OnRenderExitedEvent {
  reason: string;
}

export interface OnEngineErrorEvent {
  message: string;
}

/**
 * Shows web content rendered by Servo, like the `Web` component does with ArkWeb. The callbacks
 * mirror the `Web` events of the same name. If Servo can't run, e.g. because its native library
 * could not be loaded, the component shows the reason instead of the page and calls
 * `onEngineError`.
 */
@Component
export struct SkiffView {
  /** The URL to load first. Later changes have no effect, use the controller to navigate. */
  @Prop src: string = 'about:blank';
  controller: SkiffController = new SkiffController();
  onPageBegin: (event: OnPageBeginEvent) => void = (event: OnPageBeginEvent) => {};
  onPageEnd: (event: OnPageEndEvent) => void = (event: OnPageEndEvent) => {};
  onProgressChange: (event: OnProgressChangeEvent) => void = (event: OnProgressChangeEvent) => {};
  onTitleReceive: (event: OnTitleReceiveEvent) => void = (event: OnTitleReceiveEvent) => {};
  onUrlChange: (event: OnUrlChangeEvent) => void = (event: OnUrlChangeEvent) => {};
  onHistoryChange: (event: OnHistoryChangeEvent) => void = (event: OnHistoryChangeEvent) => {};
  onConsole: (event: OnConsoleEvent) => void = (event: OnConsoleEvent) => {};
  onAlert: (event: OnAlertEvent) => void = (event: OnAlertEvent) => {};
  onRenderExited: (event: OnRenderExitedEvent) => void = (event: OnRenderExitedEvent) => {};
  /** Called when Servo can't run, or stopped because it crashed or was shut down. */
  onEngineError: (event: OnEngineErrorEvent) => void = (event: OnEngineErrorEvent) => {};
  @State private engineError: string = '';
  private webviewId: number = 0;

  aboutToAppear(): void {
    const error = SkiffRuntime.init();
    if (error !== undefined) {
      this.fail(error);
      return;
    }
    SkiffRuntime.watchApplicationState(this.getUIContext().getHostContext());
    let id = 0;
    try {
      id = skiff.createWebView(this.src, (event: WebViewEvent) => {
        this.handleEvent(id, event);
      });
    } catch (error) {
      this.fail(`Creating the webview failed: ${(error as Error).message}`);
      return;
    }
    this.webviewId = id;
    this.controller.attach(id);
  }

  aboutToDisappear(): void {
    if (this.webviewId !== 0) {
      this.controller.detach(this.webviewId);
      skiff.destroyWebView(this.webviewId);
      this.webviewId = 0;
    }
  }

  private fail(message: string): void {
    hilog.error(0xE0C3, 'SkiffView', '%{public}s', message);
    this.engineError = message;
    this.onEngineError({ message: message });
  }

  private handleEvent(id: number, event: WebViewEvent): void {
    // Events of a webview that went away might still be queued.
    if (id !== this.webviewId) {
      return;
    }
    if (event.kind === 'engineStopped') {
      this.controller.detach(id);
      this.webviewId = 0;
      this.fail(event.message ?? 'Servo stopped');
      return;
    }
    this.controller.update(id, event);
    const url = event.url ?? '';
    const message = event.message ?? '';
    switch (event.kind) {
      case 'loadStarted':
        this.onPageBegin({ url: url });
        break;
      case 'loadFinished':
        this.onPageEnd({ url: url });
        break;
      case 'progress':
        this.onProgressChange({ newProgress: event.progress ?? 0 });
        break;
      case 'titleChanged':
        this.onTitleReceive({ title: event.title ?? '' });
        break;
      case 'urlChanged':
        this.onUrlChange({ url: url });
        break;
      case 'historyChanged':
        this.onHistoryChange({
          canGoBack: event.canGoBack ?? false,
          canGoForward: event.canGoForward ?? false,
        });
        break;
      case 'console':
        this.onConsole({ level: event.level ?? 'info', message: message });
        break;
      case 'alert':
        this.onAlert({ message: message });
        break;
      case 'crashed':
        this.onRenderExited({ reason: message });
        break;
      default:
        break;
    }
  }

  build() {
    if (this.engineError.length > 0) {
      Column({ space: 8 }) {
        Text('Servo can\'t show this page')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
        Text(this.engineError)
          .fontSize(14)
      }
      .width('100%')
      .height('100%')
      .padding(24)
      .justifyContent(FlexAlign.Center)
    } else {
      // The native side finds the webview through the XComponent id.
      XComponent({
        id: 'skiff-' + this.webviewId,
        type: XComponentType.SURFACE,
        libraryname: 'skiff',
      })
        .width('100%')
        .height('100%')
        .focusable(true)
        .focusOnTouch(true)
        .onVisibleAreaChange([0.0, 1.0], (isExpanding: boolean, currentRatio: number) => {
          if (this.webviewId !== 0) {
            skiff.setVisible(this.webviewId, currentRatio > 0);
          }
        })
    }
  }
}

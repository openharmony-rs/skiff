/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import skiff, { JavaScriptResult, WebViewEvent } from 'libskiff.so';

/**
 * Controls a `SkiffView` component, like `webview.WebviewController` controls a `Web` component.
 * A URL loaded before the component appeared loads once it did. Until then, and after the
 * component disappeared, the other methods do nothing and `runJavaScript` rejects.
 */
export class SkiffController {
  private webviewId: number = 0;
  private pendingUrl?: string;
  private url: string = '';
  private title: string = '';
  private canGoBack: boolean = false;
  private canGoForward: boolean = false;

  loadUrl(url: string): void {
    if (this.webviewId === 0) {
      this.pendingUrl = url;
      return;
    }
    skiff.loadUrl(this.webviewId, url);
  }

  refresh(): void {
    if (this.webviewId !== 0) {
      skiff.reload(this.webviewId);
    }
  }

  backward(): void {
    if (this.webviewId !== 0) {
      skiff.goBack(this.webviewId);
    }
  }

  forward(): void {
    if (this.webviewId !== 0) {
      skiff.goForward(this.webviewId);
    }
  }

  accessBackward(): boolean {
    return this.canGoBack;
  }

  accessForward(): boolean {
    return this.canGoForward;
  }

  getUrl(): string {
    return this.url;
  }

  getTitle(): string {
    return this.title;
  }

  /**
   * Closes the soft keyboard if the page has it and returns whether it had. Call it first in
   * `onBackPress`, since the back gesture reaches the page, not the keyboard.
   */
  closeSoftKeyboard(): boolean {
    return this.webviewId !== 0 && skiff.dismissSoftKeyboard(this.webviewId);
  }

  /** Runs `script` in the page and resolves with its result as JSON. */
  runJavaScript(script: string): Promise<string> {
    return new Promise<string>((resolve, reject) => {
      if (this.webviewId === 0) {
        reject(new Error('The SkiffView component is not shown'));
        return;
      }
      skiff.evaluateJavaScript(this.webviewId, script, (result: JavaScriptResult) => {
        if (result.error !== undefined) {
          reject(new Error(result.error));
        } else {
          resolve(result.result ?? 'null');
        }
      });
    });
  }

  /** Called by `SkiffView` when it created its webview. */
  attach(webviewId: number): void {
    this.reset();
    this.webviewId = webviewId;
    const pendingUrl = this.pendingUrl;
    this.pendingUrl = undefined;
    if (pendingUrl !== undefined) {
      this.loadUrl(pendingUrl);
    }
  }

  /** Called by `SkiffView` when its webview goes away. */
  detach(webviewId: number): void {
    if (this.webviewId === webviewId) {
      this.reset();
    }
  }

  /** Called by `SkiffView` for every event of its webview. */
  update(webviewId: number, event: WebViewEvent): void {
    if (this.webviewId !== webviewId) {
      return;
    }
    if (event.kind === 'urlChanged') {
      this.url = event.url ?? '';
    } else if (event.kind === 'titleChanged') {
      this.title = event.title ?? '';
    } else if (event.kind === 'historyChanged') {
      this.canGoBack = event.canGoBack ?? false;
      this.canGoForward = event.canGoForward ?? false;
    }
  }

  private reset(): void {
    this.webviewId = 0;
    this.url = '';
    this.title = '';
    this.canGoBack = false;
    this.canGoForward = false;
  }
}

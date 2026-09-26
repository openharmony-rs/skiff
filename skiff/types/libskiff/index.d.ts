/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

export interface InitOptions {
  /** Servo preferences as a JSON object. */
  preferences?: string;
  /** A log filter in `env_logger` syntax. */
  logFilter?: string;
}

export interface WebViewEvent {
  /**
   * One of `urlChanged`, `titleChanged`, `loadStarted`, `loadFinished`, `progress`,
   * `historyChanged`, `console`, `alert`, `crashed` and `engineStopped`.
   */
  kind: string;
  url?: string;
  title?: string;
  progress?: number;
  canGoBack?: boolean;
  canGoForward?: boolean;
  level?: string;
  message?: string;
}

export interface JavaScriptResult {
  /** The result as JSON. */
  result?: string;
  error?: string;
}

export interface Preference {
  name: string;
  /** `boolean`, `integer`, `unsigned` for non-negative integers, or `string`. */
  kind: string;
  /** The value that Servo uses as JSON. */
  value: string;
  defaultValue: string;
  needsRestart: boolean;
  experimental: boolean;
}

export const init: (options: InitOptions) => void;
export const shutdown: () => void;
export const createWebView: (url: string | undefined, onEvent: (event: WebViewEvent) => void) => number;
export const destroyWebView: (id: number) => void;
export const loadUrl: (id: number, url: string) => void;
export const reload: (id: number) => void;
export const goBack: (id: number) => void;
export const goForward: (id: number) => void;
export const setVisible: (id: number, visible: boolean) => void;
export const setAppVisible: (visible: boolean) => void;
export const dismissSoftKeyboard: (id: number) => boolean;
export const evaluateJavaScript: (id: number, script: string, callback: (result: JavaScriptResult) => void) => void;
export const preferences: () => Preference[];
export const setPreference: (name: string, value: string) => void;
export const servoVersion: () => string;

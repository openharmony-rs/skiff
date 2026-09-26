/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import ApplicationStateChangeCallback from '@ohos.app.ability.ApplicationStateChangeCallback';
import common from '@ohos.app.ability.common';
import deviceInfo from '@ohos.deviceInfo';
import skiff, { Preference } from 'libskiff.so';
import { HAR_VERSION } from '../../../../BuildProfile';

export type SkiffPreferenceValue = boolean | number | string;

/** A Servo preference that an app can change. */
export interface SkiffPreference {
  name: string;
  /** `boolean`, `integer`, `unsigned` for non-negative integers, or `string`. */
  kind: string;
  /** The value that Servo uses. */
  value: SkiffPreferenceValue;
  defaultValue: SkiffPreferenceValue;
  /** Whether a change only takes effect when Servo starts, not for the pages loaded after it. */
  needsRestart: boolean;
  /** Whether it enables an experimental web platform feature. */
  experimental: boolean;
}

export interface SkiffRuntimeOptions {
  /** Servo preferences overriding the defaults, e.g. `{ 'dom_geolocation_enabled': true }`. */
  preferences?: Record<string, SkiffPreferenceValue>;
  /** Servo preferences as a JSON object, e.g. from launch parameters. Replaces `preferences`. */
  preferencesJson?: string;
  /** A log filter in `env_logger` syntax, e.g. `warn,skiff_core=debug`. */
  logFilter?: string;
}

enum State {
  NotStarted,
  Running,
  ShutDown,
}

/** The ABIs that Skiff contains native libraries for. */
const PACKAGED_ABIS = ['arm64-v8a'];

/** Why the native library of Servo can't be used, or `undefined` if it loaded. */
function loadError(): string | undefined {
  // The runtime leaves the import undefined when loading the library failed.
  if (skiff !== undefined && skiff !== null && typeof skiff.init === 'function') {
    return undefined;
  }
  const abis = deviceInfo.abiList;
  if (!abis.split(',').some((abi: string) => PACKAGED_ABIS.includes(abi.trim()))) {
    return `Servo is not available for this device: it supports ${abis}, but the ` +
      `Skiff only contains ${PACKAGED_ABIS.join(', ')}.`;
  }
  return 'libskiff.so, or a library it needs, could not be loaded. hilog has the reason, ' +
    'search it for "libskiff".';
}

/** The Servo engine shared by all `SkiffView` components of the app. */
export class SkiffRuntime {
  /** The version of Skiff. */
  static readonly version: string = HAR_VERSION;
  private static state: State = State.NotStarted;
  private static watchingApplicationState: boolean = false;

  /**
   * Starts Servo, unless it runs already. The first `SkiffView` starts it with the default options,
   * so call this before to use other ones.
   *
   * Returns why Servo could not start, e.g. because the options name an unknown preference, or
   * `undefined` if it runs.
   */
  static init(options?: SkiffRuntimeOptions): string | undefined {
    if (SkiffRuntime.state === State.Running) {
      return undefined;
    }
    if (SkiffRuntime.state === State.ShutDown) {
      return 'Servo was shut down and can\'t be started again';
    }
    const error = loadError();
    if (error !== undefined) {
      return error;
    }
    const preferences = options?.preferences;
    try {
      skiff.init({
        preferences: options?.preferencesJson ??
          (preferences === undefined ? undefined : JSON.stringify(preferences)),
        logFilter: options?.logFilter,
      });
    } catch (error) {
      return `Starting Servo failed: ${(error as Error).message}`;
    }
    SkiffRuntime.state = State.Running;
    return undefined;
  }

  /** The version of Servo, or `undefined` if its native library could not be loaded. */
  static servoVersion(): string | undefined {
    return loadError() === undefined ? skiff.servoVersion() : undefined;
  }

  /**
   * The preferences that an app can change, with the values that Servo uses, or the defaults
   * before `init`. Empty if the native library of Servo could not be loaded.
   */
  static preferences(): SkiffPreference[] {
    if (loadError() !== undefined) {
      return [];
    }
    return skiff.preferences().map((preference: Preference): SkiffPreference => ({
      name: preference.name,
      kind: preference.kind,
      value: JSON.parse(preference.value) as SkiffPreferenceValue,
      defaultValue: JSON.parse(preference.defaultValue) as SkiffPreferenceValue,
      needsRestart: preference.needsRestart,
      experimental: preference.experimental,
    }));
  }

  /**
   * Changes a preference of the running Servo. Pages that load afterwards use the new value,
   * unless the preference `needsRestart`, which only `init` can set.
   *
   * Returns why the preference could not be changed, e.g. because the value has the wrong type,
   * or `undefined`.
   */
  static setPreference(name: string, value: SkiffPreferenceValue): string | undefined {
    if (SkiffRuntime.state !== State.Running) {
      return 'Servo is not running';
    }
    try {
      skiff.setPreference(name, JSON.stringify(value));
    } catch (error) {
      return (error as Error).message;
    }
    return undefined;
  }

  /**
   * Hides and throttles all webviews while the app is in the background. Called by `SkiffView`,
   * since the system does not reliably hide the surfaces before it freezes the app.
   */
  static watchApplicationState(context: common.Context | undefined): void {
    if (SkiffRuntime.watchingApplicationState || context === undefined) {
      return;
    }
    SkiffRuntime.watchingApplicationState = true;
    const callback: ApplicationStateChangeCallback = {
      onApplicationForeground: () => {
        skiff.setAppVisible(true);
      },
      onApplicationBackground: () => {
        skiff.setAppVisible(false);
      },
    };
    context.getApplicationContext().on('applicationStateChange', callback);
  }

  /**
   * Shuts Servo down, which saves cookies and other site data, and waits for it, but at most 5 s.
   * Servo can't be started again, so call this when the app exits, e.g. in `onDestroy` of its
   * ability.
   */
  static shutdown(): void {
    if (SkiffRuntime.state === State.Running) {
      skiff.shutdown();
    }
    SkiffRuntime.state = State.ShutDown;
  }
}

/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import common from '@ohos.app.ability.common';
import dataPreferences from '@ohos.data.preferences';
import hilog from '@ohos.hilog';
import { SkiffPreference, SkiffPreferenceValue } from '@openharmony-rs/skiff';

/** Whether the value has the type of a preference of the kind. */
export function fitsKind(kind: string, value: SkiffPreferenceValue): boolean {
  switch (kind) {
    case 'boolean':
      return typeof value === 'boolean';
    case 'integer':
      return typeof value === 'number' && Number.isInteger(value);
    case 'unsigned':
      return typeof value === 'number' && Number.isInteger(value) && value >= 0;
    case 'string':
      return typeof value === 'string';
    default:
      return false;
  }
}

/** The Servo preferences that the user changed, which the app starts Servo with. */
export class StoredPreferences {
  private store: dataPreferences.Preferences | undefined = undefined;

  constructor(context: common.Context) {
    try {
      this.store = dataPreferences.getPreferencesSync(context, { name: 'servo-preferences' });
    } catch (error) {
      logError('Opening the stored preferences failed', error);
    }
  }

  /**
   * The changed preferences that are among `preferences` and have a value of the right type. Forgets
   * the others, e.g. those that a newer Servo removed.
   */
  valid(preferences: SkiffPreference[]): Record<string, SkiffPreferenceValue> {
    const kinds = new Map<string, string>(
      preferences.map((preference: SkiffPreference): [string, string] => [preference.name, preference.kind]));
    const result: Record<string, SkiffPreferenceValue> = {};
    let names: string[] = [];
    try {
      names = Object.keys(this.store?.getAllSync() ?? new Object());
    } catch (error) {
      logError('Reading the stored preferences failed', error);
    }
    names.forEach((name: string) => {
      const value = this.get(name);
      const kind = kinds.get(name);
      if (value !== undefined && kind !== undefined && fitsKind(kind, value)) {
        result[name] = value;
      } else {
        this.remove(name);
      }
    });
    return result;
  }

  get(name: string): SkiffPreferenceValue | undefined {
    try {
      return this.store?.hasSync(name) ? this.store.getSync(name, '') as SkiffPreferenceValue : undefined;
    } catch (error) {
      logError(`Reading the stored preference ${name} failed`, error);
      return undefined;
    }
  }

  set(name: string, value: SkiffPreferenceValue): void {
    try {
      this.store?.putSync(name, value);
      this.store?.flushSync();
    } catch (error) {
      logError(`Storing the preference ${name} failed`, error);
    }
  }

  remove(name: string): void {
    try {
      this.store?.deleteSync(name);
      this.store?.flushSync();
    } catch (error) {
      logError(`Forgetting the stored preference ${name} failed`, error);
    }
  }
}

function logError(message: string, error: Object): void {
  hilog.error(0x0000, 'SkiffDemo', '%{public}s: %{public}s', message, (error as Error).message);
}

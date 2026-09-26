/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import hilog from '@ohos.hilog';
import UIAbility from '@ohos.app.ability.UIAbility';
import Want from '@ohos.app.ability.Want';
import window from '@ohos.window';
import { SkiffPreferenceValue, SkiffRuntime } from '@openharmony-rs/skiff';
import { StoredPreferences } from '../common/StoredPreferences';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'SkiffDemo';
const DEFAULT_URL = 'https://servo.org';

/**
 * Reads the want parameters, given as `aa start --ps <name> <value>` or `aa start --psn <name>=<value>`.
 * A leading `--` of the name is ignored, so `--psn --chrome=none` works like for servoshell.
 */
function readParameters(want: Want): Map<string, string> {
  const result = new Map<string, string>();
  if (want.parameters === undefined) {
    return result;
  }
  Object.entries(want.parameters).forEach((entry) => {
    let name: string = entry[0];
    let value: string = entry[1] !== null && entry[1] !== undefined ? entry[1].toString() : '';
    const separator = name.indexOf('=');
    if (value.length === 0 && separator > 0) {
      value = name.substring(separator + 1);
      name = name.substring(0, separator);
    }
    if (name.startsWith('--')) {
      name = name.substring(2);
    }
    result.set(name, value);
  });
  return result;
}

/**
 * Launch parameters:
 * - `chrome=none` hides the toolbar, so that the page fills the window.
 * - `prefs=<json>` sets Servo preferences, e.g. `prefs={"js_ion_enabled":false}`, on top
 *   of those changed on the preferences page.
 * - `log=<filter>` sets the log filter, e.g. `log=warn,skiff_core=debug`.
 * - `eval=<script>` runs the script whenever a page finished loading and logs the result.
 */
export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    const parameters = readParameters(want);
    const chrome = parameters.get('chrome') ?? '';
    AppStorage.setOrCreate<string>('initialUrl', want.uri ? want.uri : DEFAULT_URL);
    AppStorage.setOrCreate<boolean>('showChrome', !(chrome === 'none' || chrome === 'false' || chrome === '0'));
    AppStorage.setOrCreate<string>('evalScript', parameters.get('eval') ?? '');
    const preferences = new StoredPreferences(this.context).valid(SkiffRuntime.preferences());
    const launchPreferences = parameters.get('prefs');
    if (launchPreferences !== undefined) {
      try {
        const values = JSON.parse(launchPreferences) as Record<string, SkiffPreferenceValue>;
        Object.keys(values).forEach((name: string) => {
          preferences[name] = values[name];
        });
      } catch (error) {
        hilog.error(LOG_DOMAIN, LOG_TAG, 'Ignoring the invalid prefs parameter: %{public}s',
          (error as Error).message);
      }
    }
    const error = SkiffRuntime.init({
      preferences: preferences,
      logFilter: parameters.get('log'),
    });
    if (error !== undefined) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Servo could not start: %{public}s', error);
    }
  }

  onDestroy(): void {
    // Saves cookies and other site data.
    SkiffRuntime.shutdown();
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    if (want.uri) {
      AppStorage.setOrCreate<string>('loadUrl', want.uri);
      AppStorage.setOrCreate<number>('loadUrlRequest', (AppStorage.get<number>('loadUrlRequest') ?? 0) + 1);
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to load the content: %{public}s', JSON.stringify(err));
      }
    });
  }
}

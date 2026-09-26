/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { abilityDelegatorRegistry, TestRunner } from '@kit.TestKit';

/** Starts `TestAbility`, which runs the tests. */
export default class OpenHarmonyTestRunner implements TestRunner {
  onPrepare() {
  }

  onRun() {
    const delegator = abilityDelegatorRegistry.getAbilityDelegator();
    const args = abilityDelegatorRegistry.getArguments();
    const want: Want = {
      bundleName: args.bundleName,
      abilityName: 'TestAbility',
      moduleName: args.parameters['-m'],
    };
    delegator.startAbility(want).catch((error: BusinessError) => {
      hilog.error(0x0000, 'SkiffTest', 'Starting TestAbility failed: %{public}s', error.message);
    });
  }
}

/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import { UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { Hypium } from '@ohos/hypium';
import testsuite from '../test/List.test';
import * as Harness from './Harness';

/** Runs the tests, while its page shows the `SkiffView` components they create. */
export default class TestAbility extends UIAbility {
  onCreate() {
    Hypium.hypiumTest(abilityDelegatorRegistry.getAbilityDelegator(),
      abilityDelegatorRegistry.getArguments(), testsuite);
  }

  onWindowStageCreate(windowStage: window.WindowStage) {
    Harness.setMainWindow(windowStage.getMainWindowSync());
    windowStage.loadContent('testability/pages/Index', (error) => {
      if (error.code) {
        hilog.error(0x0000, 'SkiffTest', 'Loading the test page failed: %{public}s', error.message);
      }
    });
  }
}

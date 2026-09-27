/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import { afterAll, beforeAll, describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, MatchPattern, ON } from '@kit.TestKit';
import { SkiffPreference, SkiffRuntime } from '@openharmony-rs/skiff';
import * as Harness from '../testability/Harness';

const delegator = abilityDelegatorRegistry.getAbilityDelegator();
const bundleName = abilityDelegatorRegistry.getArguments().bundleName;

function experimentalValues(): string {
  return SkiffRuntime.preferences()
    .filter((preference: SkiffPreference) => preference.experimental)
    .map((preference: SkiffPreference) => preference.value.toString())
    .join();
}

/** Opens a page from the menu, and waits until the menu, which would take taps, closed. */
async function openMenuItem(driver: Driver, item: string): Promise<void> {
  try {
    await (await driver.waitForComponent(ON.id('menu'), 5000)).click();
    await (await driver.waitForComponent(ON.text(item).type('Option'), 5000)).click();
    await Harness.waitUntil(async () => {
      const option = await driver.findComponent(ON.type('Option'));
      return option === null || option === undefined;
    }, 'the menu to close');
    await driver.waitForIdle(500, 5000);
  } catch (error) {
    throw new Error(`Opening ${item} from the menu failed: ${(error as Error).message}`);
  }
}

/**
 * Drives the demo app, which runs in the same process as the tests, so it has to come before
 * `SkiffRuntimeShutdown`. Leaves it in the background, since closing it shuts Servo down.
 */
export default function demoAppTest() {
  describe('DemoApp', () => {
    beforeAll(async () => {
      await delegator.startAbility({
        bundleName: bundleName,
        abilityName: 'EntryAbility',
        uri: Harness.page('Demo'),
      });
    });

    afterAll(async () => {
      await delegator.startAbility({
        bundleName: bundleName,
        abilityName: 'TestAbility',
        moduleName: 'entry_test',
      });
    });

    it('showsAboutPageAndLicenses', 0, async () => {
      const driver = Driver.create();
      await openMenuItem(driver, 'About');
      const version = await (await driver.waitForComponent(ON.id('engine-version'), 5000)).getText();
      expect(version).assertContain(`Skiff ${SkiffRuntime.version}`);
      expect(version).assertContain(`Servo ${SkiffRuntime.servoVersion()}`);
      await driver.assertComponentExist(ON.text('The FreeType Project', MatchPattern.CONTAINS));

      await (await driver.findComponent(ON.id('open-licenses'))).click();
      await driver.waitForComponent(ON.text('servo:license'), 10000);
    });

    it('switchesExperimentalFeatures', 0, async () => {
      const driver = Driver.create();
      const defaults = experimentalValues();
      await openMenuItem(driver, 'Preferences');
      await (await driver.waitForComponent(ON.id('experimental'), 5000)).click();
      await Harness.waitUntil(async () => !experimentalValues().includes('false'),
        'the experimental features to be on');
      await (await driver.findComponent(ON.id('experimental'))).click();
      await Harness.waitUntil(async () => experimentalValues() === defaults,
        'the experimental features to be off');
      await driver.pressBack();
      await driver.waitForComponent(ON.id('menu'), 5000);
    });
  });
}

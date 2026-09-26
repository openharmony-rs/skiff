/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import { afterEach, describe, expect, it } from '@ohos/hypium';
import { KeyCode } from '@kit.InputKit';
import { Driver, ON } from '@kit.TestKit';
import * as Harness from '../testability/Harness';
import { bounds, pointIn } from '../testability/Screen';

const INPUT_PAGE = Harness.page('Input',
  '<body style="margin:0"><input id="field" style="width:100%;height:40vh;font-size:48px">');

async function activeElementId(slot: Harness.Slot): Promise<string> {
  return JSON.parse(await slot.controller.runJavaScript('document.activeElement.id')) as string;
}

async function fieldValue(slot: Harness.Slot): Promise<string> {
  return JSON.parse(
    await slot.controller.runJavaScript('document.getElementById("field").value')) as string;
}

/** Taps the field of `INPUT_PAGE` and waits until it has the focus and the soft keyboard shows. */
async function focusField(driver: Driver, slot: Harness.Slot): Promise<void> {
  const field = pointIn(await bounds(driver, slot), 0.5, 0.2);
  await driver.click(field.x, field.y);
  await Harness.waitUntil(async () => await activeElementId(slot) === 'field', 'the field to be focused');
  await Harness.waitUntil(async () => Harness.keyboardHeight() > 0, 'the soft keyboard to show');
}

export default function inputTest() {
  describe('SkiffViewInput', () => {
    afterEach(() => {
      Harness.clear();
    });

    it('followsTappedLink', 0, async () => {
      const driver = Driver.create();
      const target = Harness.page('Target');
      const slot = Harness.show(Harness.page('Link',
        `<body style="margin:0"><a href="${target}" style="display:block;height:100vh">Go</a>`));
      await slot.waitFor('pageEnd');
      const center = pointIn(await bounds(driver, slot));
      slot.mark();
      await driver.click(center.x, center.y);
      await slot.waitFor('pageEnd', target);
      expect(slot.values('pageBegin').join()).assertEqual(target);
      expect(slot.controller.getTitle()).assertEqual('Target');
    });

    it('scrollsOnSwipe', 0, async () => {
      const driver = Driver.create();
      const slot = Harness.show(Harness.page('Long', '<div style="height:5000px"></div>'));
      await slot.waitFor('pageEnd');
      const rect = await bounds(driver, slot);
      const from = pointIn(rect, 0.5, 0.8);
      const to = pointIn(rect, 0.5, 0.3);
      await driver.swipe(from.x, from.y, to.x, to.y, 2000);
      await Harness.waitUntil(async () => Number(await slot.controller.runJavaScript('window.scrollY')) > 0,
        'the page to scroll');
    });

    it('typesAndClosesKeyboardOnBack', 0, async () => {
      const driver = Driver.create();
      const slot = Harness.show(INPUT_PAGE);
      await slot.waitFor('pageEnd');
      await focusField(driver, slot);
      await driver.triggerKey(KeyCode.KEYCODE_A);
      await Harness.waitUntil(async () => await fieldValue(slot) === 'a', 'the key to be typed');
      await driver.pressBack();
      await Harness.waitUntil(async () => Harness.backPressResults().length === 1, 'the back press');
      expect(Harness.backPressResults()[0]).assertTrue();
      await Harness.waitUntil(async () => await activeElementId(slot) === '', 'the field to be blurred');
      await Harness.waitUntil(async () => Harness.keyboardHeight() === 0, 'the soft keyboard to hide');
      await driver.pressBack();
      await Harness.waitUntil(async () => Harness.backPressResults().length === 2, 'the back press');
      expect(Harness.backPressResults()[1]).assertFalse();
    });

    it('handsKeyboardToArkUiAndBack', 0, async () => {
      const driver = Driver.create();
      Harness.showTextInput();
      const slot = Harness.show(INPUT_PAGE);
      await slot.waitFor('pageEnd');
      await focusField(driver, slot);

      // The page must not close the input session of the ArkUI field when it loses the focus.
      await (await driver.findComponent(ON.id('arkui-input'))).click();
      await Harness.waitUntil(async () => await activeElementId(slot) === '', 'the field to be blurred');
      await Harness.sleep(500);
      expect(Harness.keyboardHeight()).assertLarger(0);
      await (await driver.findComponent(ON.id('arkui-input'))).inputText('arkui');
      expect(await (await driver.findComponent(ON.id('arkui-input'))).getText()).assertEqual('arkui');

      // Tapping the field of the page again gives it the keyboard back.
      await focusField(driver, slot);
      await driver.triggerKey(KeyCode.KEYCODE_B);
      await Harness.waitUntil(async () => await fieldValue(slot) === 'b', 'the key to be typed');
      expect(await (await driver.findComponent(ON.id('arkui-input'))).getText()).assertEqual('arkui');
      expect(slot.controller.closeSoftKeyboard()).assertTrue();
      await Harness.waitUntil(async () => Harness.keyboardHeight() === 0, 'the soft keyboard to hide');
    });
  });
}

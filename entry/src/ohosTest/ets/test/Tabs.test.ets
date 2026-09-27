/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import { afterEach, describe, expect, it } from '@ohos/hypium';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Driver } from '@kit.TestKit';
import * as Harness from '../testability/Harness';
import {
  bounds, GRAY, GREEN, Point, pointIn, waitForAnimation, waitForColor,
} from '../testability/Screen';

function coloredPage(title: string, color: string): string {
  return Harness.page(title, `<body style="margin:0;background:${color}">`);
}

/**
 * Opens, switches and closes tabs, each a `SkiffView`, like a browser would, with the inactive
 * tabs set to `hidden`.
 */
async function exerciseTabs(driver: Driver, hidden: Visibility): Promise<void> {
  Harness.useTabs(hidden);

  const first = Harness.show(coloredPage('First', '#00ff00'));
  await first.waitFor('pageEnd');
  const center: Point = pointIn(await bounds(driver, first));
  await waitForColor(driver, center, GREEN, 'the first tab');
  await first.controller.runJavaScript('window.state = "kept"');

  const second = Harness.show(Harness.animationPage('Second'));
  await second.waitFor('pageEnd');
  await waitForAnimation(driver, center, 'the second tab');

  // The hidden tab keeps its page.
  first.mark();
  expect(await first.controller.runJavaScript('window.state')).assertEqual('"kept"');
  Harness.activate(first);
  await waitForColor(driver, center, GREEN, 'the first tab again');
  expect(first.values('pageBegin').length).assertEqual(0);

  // Hidden tabs are throttled.
  const frames = await Harness.frameCount(second);
  await Harness.sleep(1000);
  const hiddenFrames = await Harness.frameCount(second) - frames;
  hilog.info(0x0000, 'SkiffTest', 'Frames of a hidden tab in 1 s: %{public}d', hiddenFrames);
  expect(hiddenFrames).assertLess(10);

  for (let i = 0; i < 5; i++) {
    Harness.activate(second);
    await Harness.sleep(50);
    Harness.activate(first);
    await Harness.sleep(50);
  }
  Harness.activate(second);
  await waitForAnimation(driver, center, 'the second tab again');

  const third = Harness.show(coloredPage('Third', '#808080'));
  await third.waitFor('pageEnd');
  await waitForColor(driver, center, GRAY, 'the third tab');

  // Closing the active tab shows the last one.
  Harness.remove(third);
  await Harness.waitUntil(async () => third.controller.getUrl() === '', 'the third tab to close');
  await expect(third.controller.runJavaScript('1')).assertPromiseIsRejected();
  await waitForAnimation(driver, center, 'the second tab after closing the third');
  Harness.remove(second);
  await waitForColor(driver, center, GREEN, 'the first tab after closing the others');
  expect(await first.controller.runJavaScript('window.state')).assertEqual('"kept"');
}

export default function tabsTest() {
  describe('SkiffViewTabs', () => {
    afterEach(() => {
      Harness.clear();
    });

    it('switchesTabsKeptInLayout', 0, async () => {
      await exerciseTabs(Driver.create(), Visibility.Hidden);
    });

    it('switchesTabsRemovedFromLayout', 0, async () => {
      await exerciseTabs(Driver.create(), Visibility.None);
    });
  });
}

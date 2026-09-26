/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import { afterEach, describe, expect, it } from '@ohos/hypium';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Driver } from '@kit.TestKit';
import * as Harness from '../testability/Harness';
import { bounds, colorsAt, GREEN, MAGENTA, pointIn, waitForColor } from '../testability/Screen';

export default function renderingTest() {
  describe('SkiffViewRendering', () => {
    afterEach(() => {
      Harness.clear();
    });

    it('rendersPage', 0, async () => {
      const driver = Driver.create();
      const slot = Harness.show(Harness.page('Green', '<body style="margin:0;background:#00ff00">'));
      await slot.waitFor('pageEnd');
      const center = pointIn(await bounds(driver, slot));
      await waitForColor(driver, center, GREEN, 'a green page');
      slot.mark();
      slot.controller.loadUrl(Harness.page('Magenta', '<body style="margin:0;background:#ff00ff">'));
      await slot.waitFor('pageEnd');
      await waitForColor(driver, center, MAGENTA, 'a magenta page');
    });

    it('animatesTwoWebviewsAtOnce', 0, async () => {
      const driver = Driver.create();
      const slots = [
        Harness.show(Harness.animationPage('Top')),
        Harness.show(Harness.animationPage('Bottom')),
      ];
      for (const slot of slots) {
        await slot.waitFor('pageEnd');
      }

      const before = [await Harness.frameCount(slots[0]), await Harness.frameCount(slots[1])];
      await Harness.sleep(1000);
      const after = [await Harness.frameCount(slots[0]), await Harness.frameCount(slots[1])];
      hilog.info(0x0000, 'SkiffTest', 'Frames in 1 s: %{public}d, %{public}d',
        after[0] - before[0], after[1] - before[1]);
      expect(after[0] - before[0]).assertLarger(20);
      expect(after[1] - before[1]).assertLarger(20);

      // Both pages have to reach the screen, not only animate.
      const points = [pointIn(await bounds(driver, slots[0])), pointIn(await bounds(driver, slots[1]))];
      const shots: number[][][] = [];
      for (let i = 0; i < 4; i++) {
        shots.push(await colorsAt(driver, points));
      }
      for (let slot = 0; slot < 2; slot++) {
        const colors = new Set<string>(shots.map((shot: number[][]) => shot[slot].join()));
        expect(colors.size).assertLargerOrEqual(3);
      }
    });
  });
}

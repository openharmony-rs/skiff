/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import { afterEach, describe, expect, it } from '@ohos/hypium';
import { display } from '@kit.ArkUI';
import { Driver } from '@kit.TestKit';
import * as Harness from '../testability/Harness';
import { bounds, GREEN, MAGENTA, Point, waitForColor } from '../testability/Screen';

async function evaluateNumber(slot: Harness.Slot, script: string): Promise<number> {
  return Number(await slot.controller.runJavaScript(script));
}

/** Waits until the viewport of the page has the size of the slot, in CSS pixels. */
async function waitForViewportOfSlot(driver: Driver, slot: Harness.Slot): Promise<void> {
  let density = 1;
  try {
    density = display.getDefaultDisplaySync().densityPixels;
  } catch (error) {
    throw new Error(`Getting the display density failed: ${(error as Error).message}`);
  }
  let expected = '';
  let actual = '';
  try {
    await Harness.waitUntil(async () => {
      const rect = await bounds(driver, slot);
      const width = (rect.right - rect.left) / density;
      const height = (rect.bottom - rect.top) / density;
      const innerWidth = await evaluateNumber(slot, 'innerWidth');
      const innerHeight = await evaluateNumber(slot, 'innerHeight');
      expected = `${width}x${height}`;
      actual = `${innerWidth}x${innerHeight}`;
      return Math.abs(innerWidth - width) <= 1 && Math.abs(innerHeight - height) <= 1;
    }, 'the viewport to have the size of the slot');
  } catch (error) {
    throw new Error(`${(error as Error).message}: expected ${expected}, got ${actual}`);
  }
}

export default function viewportTest() {
  describe('SkiffViewViewport', () => {
    afterEach(() => {
      Harness.clear();
    });

    it('matchesDisplayDensity', 0, async () => {
      const slot = Harness.show(Harness.page('Density'));
      await slot.waitFor('pageEnd');
      const devicePixelRatio = await evaluateNumber(slot, 'devicePixelRatio');
      expect(devicePixelRatio).assertClose(display.getDefaultDisplaySync().densityPixels, 0.01);
    });

    it('matchesComponentSize', 0, async () => {
      const slot = Harness.show(Harness.page('Size'));
      await slot.waitFor('pageEnd');
      await waitForViewportOfSlot(Driver.create(), slot);
    });

    it('resizesWithComponent', 0, async () => {
      const driver = Driver.create();
      const top = Harness.show(Harness.page('Top',
        '<script>window.resizes = 0; onresize = () => window.resizes++;</script>'));
      await top.waitFor('pageEnd');
      await waitForViewportOfSlot(driver, top);
      const fullHeight = await evaluateNumber(top, 'innerHeight');

      const bottom = Harness.show(Harness.page('Bottom'));
      await bottom.waitFor('pageEnd');
      await waitForViewportOfSlot(driver, top);
      await waitForViewportOfSlot(driver, bottom);
      expect(await evaluateNumber(top, 'innerHeight')).assertLess(fullHeight * 0.6);
      expect(await evaluateNumber(top, 'window.resizes')).assertLargerOrEqual(1);

      Harness.remove(bottom);
      await waitForViewportOfSlot(driver, top);
      expect(await evaluateNumber(top, 'innerHeight')).assertClose(fullHeight, 1);
    });

    it('appliesViewportInitialScale', 0, async () => {
      const driver = Driver.create();
      const density = display.getDefaultDisplaySync().densityPixels;
      const body = '<body style="margin:0;background:#ff00ff">' +
        '<div style="width:100px;height:100px;background:#00ff00"></div>';
      const slot = Harness.show(Harness.page('Unscaled', body));
      await slot.waitFor('pageEnd');
      const rect = await bounds(driver, slot);
      const width = (rect.right - rect.left) / density;
      // Right of the green square, unless the page is scaled by 2.
      const point: Point = {
        x: rect.left + Math.round(150 * density),
        y: rect.top + Math.round(50 * density),
      };
      await waitForColor(driver, point, MAGENTA, 'the page right of the square');
      expect(await evaluateNumber(slot, 'innerWidth')).assertClose(width, 1);

      // The layout viewport becomes half as wide, and is shown twice as large.
      slot.mark();
      const scaled = Harness.page('Scaled', '<meta name="viewport" content="initial-scale=2">' + body);
      slot.controller.loadUrl(scaled);
      await slot.waitFor('pageEnd', scaled);
      await waitForColor(driver, point, GREEN, 'the square, scaled by 2');
      expect(await evaluateNumber(slot, 'innerWidth')).assertClose(width / 2, 1);
    });
  });
}

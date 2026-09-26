/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import { afterEach, describe, expect, it } from '@ohos/hypium';
import * as Harness from '../testability/Harness';

/** The titles that the slot received, without the empty ones of new documents. */
function titles(slot: Harness.Slot): string {
  return slot.values('title').filter((title: string) => title.length > 0).join();
}

export default function lifecycleTest() {
  describe('SkiffViewLifecycle', () => {
    afterEach(() => {
      Harness.clear();
    });

    it('detachesControllerWhenRemoved', 0, async () => {
      const first = Harness.page('One');
      const second = Harness.page('Two');
      const slot = Harness.show(first);
      await slot.waitFor('pageEnd', first);
      slot.controller.loadUrl(second);
      await slot.waitFor('history', 'true,false');
      Harness.remove(slot);
      await Harness.waitUntil(async () => slot.controller.getUrl() === '', 'the controller to detach');
      expect(slot.controller.getTitle()).assertEqual('');
      expect(slot.controller.accessBackward()).assertFalse();
      await expect(slot.controller.runJavaScript('1')).assertPromiseIsRejected();
    });

    it('reattachesController', 0, async () => {
      const first = Harness.show(Harness.page('Before'));
      await first.waitFor('pageEnd');
      Harness.remove(first);
      await Harness.waitUntil(async () => first.controller.getUrl() === '', 'the controller to detach');
      const url = Harness.page('After');
      const second = Harness.show(url, first.controller);
      await second.waitFor('pageEnd', url);
      expect(await first.controller.runJavaScript('document.title')).assertEqual('"After"');
      expect(first.controller.accessBackward()).assertFalse();
    });

    it('showsTwoWebviews', 0, async () => {
      const top = Harness.show(Harness.page('Top'));
      const bottom = Harness.show(Harness.page('Bottom'));
      await top.waitFor('pageEnd', top.src);
      await bottom.waitFor('pageEnd', bottom.src);
      expect(await top.controller.runJavaScript('document.title')).assertEqual('"Top"');
      expect(await bottom.controller.runJavaScript('document.title')).assertEqual('"Bottom"');
      expect(titles(top)).assertEqual('Top');
      expect(titles(bottom)).assertEqual('Bottom');
      bottom.controller.loadUrl(Harness.page('Next'));
      await bottom.waitFor('title', 'Next');
      expect(top.controller.getTitle()).assertEqual('Top');
      expect(titles(top)).assertEqual('Top');
    });

    it('ignoresEventsAfterRemoval', 0, async () => {
      const slot = Harness.show(Harness.page('Ticks',
        '<script>setInterval(() => console.log("tick"), 20)</script>'));
      await slot.waitFor('console', 'info:tick');
      Harness.remove(slot);
      await Harness.sleep(100);
      const count = slot.events.length;
      await Harness.sleep(500);
      expect(slot.events.length).assertEqual(count);
    });
  });
}

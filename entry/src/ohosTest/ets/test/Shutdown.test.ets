/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import { afterEach, describe, expect, it } from '@ohos/hypium';
import { Driver, ON } from '@kit.TestKit';
import { SkiffRuntime } from '@openharmony-rs/skiff';
import * as Harness from '../testability/Harness';

/** Shuts Servo down for good, so it has to be the last suite. */
export default function shutdownTest() {
  describe('SkiffRuntimeShutdown', () => {
    afterEach(() => {
      Harness.clear();
    });

    it('stopsWebviews', 0, async () => {
      const slot = Harness.show(Harness.page('Last'));
      await slot.waitFor('pageEnd');
      SkiffRuntime.shutdown();
      await slot.waitFor('engineError', 'Servo was shut down');
      await Driver.create().assertComponentExist(ON.text('Servo can\'t show this page'));
      await expect(slot.controller.runJavaScript('1')).assertPromiseIsRejected();
    });

    it('cannotStartAgain', 0, async () => {
      expect(SkiffRuntime.init()).assertContain('can\'t be started again');
      const slot = Harness.show(Harness.page('Late'));
      await slot.waitFor('engineError');
      expect(slot.values('pageBegin').length).assertEqual(0);
    });
  });
}

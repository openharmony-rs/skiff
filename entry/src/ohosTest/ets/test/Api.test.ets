/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import { afterEach, describe, expect, it } from '@ohos/hypium';
import { SkiffController } from '@openharmony-rs/skiff';
import * as Harness from '../testability/Harness';

interface Nested {
  list: (number | boolean | null)[];
  text: string;
}

export default function apiTest() {
  describe('SkiffViewApi', () => {
    afterEach(() => {
      Harness.clear();
    });

    it('reportsPageLoad', 0, async () => {
      const url = Harness.page('First', '<p>Hello</p>');
      const slot = Harness.show(url);
      await slot.waitFor('pageEnd', url);
      const kinds = slot.kinds();
      expect(kinds.indexOf('pageBegin')).assertLargerOrEqual(0);
      expect(kinds.indexOf('pageBegin')).assertLess(kinds.indexOf('url'));
      expect(kinds.indexOf('url')).assertLess(kinds.indexOf('pageEnd'));
      expect(slot.values('pageBegin').join()).assertEqual(url);
      expect(slot.values('url').join()).assertEqual(url);
      expect(slot.values('title')).assertContain('First');
      expect(slot.values('progress').join()).assertEqual('10,60,100');
      expect(slot.values('history').join()).assertEqual('false,false');
      expect(slot.values('engineError').length).assertEqual(0);
      expect(slot.controller.getUrl()).assertEqual(url);
      expect(slot.controller.getTitle()).assertEqual('First');
    });

    it('runJavaScriptResolvesWithJson', 0, async () => {
      const url = Harness.page('Script');
      const slot = Harness.show(url);
      await slot.waitFor('pageEnd', url);
      const controller = slot.controller;
      expect(await controller.runJavaScript('1 + 1')).assertEqual('2');
      expect(await controller.runJavaScript('0.5')).assertEqual('0.5');
      expect(await controller.runJavaScript('"a" + "b"')).assertEqual('"ab"');
      expect(await controller.runJavaScript('undefined')).assertEqual('null');
      expect(await controller.runJavaScript('document.title')).assertEqual('"Script"');
      const nested = JSON.parse(
        await controller.runJavaScript('({ list: [1, true, null], text: "x" })')) as Nested;
      expect(nested.text).assertEqual('x');
      expect(JSON.stringify(nested.list)).assertEqual('[1,true,null]');
    });

    it('runJavaScriptRejectsWhenScriptThrows', 0, async () => {
      const url = Harness.page('Throws');
      const slot = Harness.show(url);
      await slot.waitFor('pageEnd', url);
      await expect(slot.controller.runJavaScript('throw new Error("boom")')).assertPromiseIsRejected();
      expect(await slot.controller.runJavaScript('1')).assertEqual('1');
    });

    it('runJavaScriptRejectsBeforeAppear', 0, async () => {
      const controller = new SkiffController();
      await expect(controller.runJavaScript('1')).assertPromiseIsRejected();
    });

    it('loadsUrlRequestedBeforeAppear', 0, async () => {
      const controller = new SkiffController();
      const url = Harness.page('Requested');
      controller.loadUrl(url);
      const slot = Harness.show(Harness.page('Src'), controller);
      await slot.waitFor('pageEnd', url);
      expect(controller.getUrl()).assertEqual(url);
      expect(controller.getTitle()).assertEqual('Requested');
    });

    it('navigatesHistory', 0, async () => {
      const first = Harness.page('One');
      const second = Harness.page('Two');
      const slot = Harness.show(first);
      const controller = slot.controller;
      await slot.waitFor('pageEnd', first);
      expect(controller.accessBackward()).assertFalse();

      slot.mark();
      controller.loadUrl(second);
      await slot.waitFor('pageEnd', second);
      expect(slot.values('pageBegin').join()).assertEqual(second);
      expect(slot.values('history').join()).assertEqual('true,false');
      expect(controller.accessBackward()).assertTrue();
      expect(controller.accessForward()).assertFalse();

      slot.mark();
      controller.backward();
      await slot.waitFor('history', 'false,true');
      await slot.waitFor('url', first);
      expect(controller.getUrl()).assertEqual(first);
      expect(controller.accessForward()).assertTrue();

      slot.mark();
      controller.forward();
      await slot.waitFor('history', 'true,false');
      await slot.waitFor('url', second);
      expect(controller.getUrl()).assertEqual(second);
    });

    it('refreshReloads', 0, async () => {
      const url = Harness.page('Reload', '<script>console.log("loaded")</script>');
      const slot = Harness.show(url);
      await slot.waitFor('pageEnd', url);
      await slot.waitFor('console', 'info:loaded');
      slot.mark();
      slot.controller.refresh();
      await slot.waitFor('pageEnd', url);
      await slot.waitFor('console', 'info:loaded');
      expect(slot.values('pageBegin').join()).assertEqual(url);
    });

    it('reportsConsoleAndAlert', 0, async () => {
      const url = Harness.page('Messages',
        '<script>console.warn("careful"); console.error("broken"); alert("hi")</script>');
      const slot = Harness.show(url);
      await slot.waitFor('console', 'warn:careful');
      await slot.waitFor('console', 'error:broken');
      await slot.waitFor('alert', 'hi');
    });
  });
}

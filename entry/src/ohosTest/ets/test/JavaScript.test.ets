/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import { afterEach, describe, expect, it } from '@ohos/hypium';
import * as Harness from '../testability/Harness';

/** How the promise settled: `resolved <value>`, `rejected <message>` or `pending` after 5 s. */
async function outcome(promise: Promise<string>): Promise<string> {
  const timeout = new Promise<string>((resolve) => setTimeout(() => resolve('pending'), 5000));
  const settled = promise.then((value: string) => `resolved ${value}`,
    (error: Error) => `rejected ${error.message}`);
  return Promise.race([settled, timeout]);
}

/** Runs a script that keeps the page busy for the given time and then returns 1. */
function busyScript(ms: number): string {
  return `const end = Date.now() + ${ms}; while (Date.now() < end) {} 1`;
}

export default function javaScriptTest() {
  describe('SkiffViewJavaScript', () => {
    afterEach(() => {
      Harness.clear();
    });

    it('resolvesConcurrentCalls', 0, async () => {
      const slot = Harness.show(Harness.page('Concurrent'));
      await slot.waitFor('pageEnd');
      const calls: Promise<string>[] = [];
      for (let i = 0; i < 50; i++) {
        calls.push(slot.controller.runJavaScript(`${i} * 2`));
      }
      const results = await Promise.all(calls);
      results.forEach((result: string, i: number) => {
        expect(result).assertEqual(`${i * 2}`);
      });
    });

    it('roundTripsUnicode', 0, async () => {
      const text = 'Grüße 🌍 中文 "quoted" \\ back\nslash';
      const url = Harness.page('Tïtle 🌍 中文', `<script>console.log(${JSON.stringify(text)})</script>`);
      const slot = Harness.show(url);
      await slot.waitFor('pageEnd', url);
      expect(slot.controller.getTitle()).assertEqual('Tïtle 🌍 中文');
      await slot.waitFor('console', `info:${text}`);
      expect(JSON.parse(await slot.controller.runJavaScript(JSON.stringify(text)))).assertEqual(text);
      expect(JSON.parse(await slot.controller.runJavaScript('"🌍".length'))).assertEqual(2);
    });

    it('convertsValuesThatJsonCannotHold', 0, async () => {
      const slot = Harness.show(Harness.page('Values', '<p id="p">text</p>'));
      await slot.waitFor('pageEnd');
      const run = (script: string) => outcome(slot.controller.runJavaScript(script));
      expect(await run('NaN')).assertEqual('resolved null');
      expect(await run('Infinity')).assertEqual('resolved null');
      expect(await run('-0')).assertEqual('resolved 0');
      expect(await run('2 ** 60 === Number(2 ** 60)')).assertEqual('resolved true');
      expect(JSON.parse((await run('2 ** 60')).substring(9))).assertEqual(2 ** 60);
      expect(await run('[1, [2, [3]]]')).assertEqual('resolved [1,[2,[3]]]');
      expect(await run('(() => { const a = {}; a.self = a; return a; })()')).assertContain('rejected');
      expect(await run('document.getElementById("p")')).assertContain('resolved "');
      expect(await run('Promise.resolve(1)')).assertEqual('resolved {}');
      expect(await run('() => 1')).assertContain('resolved');
      expect(await run('Symbol("s")')).assertContain('rejected');
      expect(await run('syntax error here')).assertContain('rejected');
    });

    it('settlesWhenPageNavigatesAway', 0, async () => {
      const slot = Harness.show(Harness.page('Before'));
      await slot.waitFor('pageEnd');
      const busy = slot.controller.runJavaScript(busyScript(300));
      slot.controller.loadUrl(Harness.page('After'));
      const title = slot.controller.runJavaScript('document.title');
      expect(await outcome(busy)).assertEqual('resolved 1');
      expect(await outcome(title)).not().assertEqual('pending');
      await slot.waitFor('pageEnd', Harness.page('After'));
      expect(await slot.controller.runJavaScript('document.title')).assertEqual('"After"');
    });

    it('settlesWhenRemoved', 0, async () => {
      const slot = Harness.show(Harness.page('Removed'));
      await slot.waitFor('pageEnd');
      const busy = slot.controller.runJavaScript(busyScript(300));
      const queued = slot.controller.runJavaScript('1');
      Harness.remove(slot);
      expect(await outcome(busy)).not().assertEqual('pending');
      expect(await outcome(queued)).not().assertEqual('pending');
    });

    it('settlesDuringFirstLoad', 0, async () => {
      const slot = Harness.show(Harness.page('Loading', `<script>${busyScript(300)}</script>`));
      await slot.waitFor('pageBegin');
      expect(await outcome(slot.controller.runJavaScript('1'))).not().assertEqual('pending');
    });
  });
}

/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import { afterEach, beforeAll, describe, expect, it } from '@ohos/hypium';
import { SkiffPreference, SkiffRuntime } from '@openharmony-rs/skiff';
import * as Harness from '../testability/Harness';

function preference(name: string): SkiffPreference | undefined {
  return SkiffRuntime.preferences().find((preference: SkiffPreference) => preference.name === name);
}

async function hasIntersectionObserver(slot: Harness.Slot): Promise<boolean> {
  return JSON.parse(await slot.controller.runJavaScript('"IntersectionObserver" in window')) as boolean;
}

export default function preferencesTest() {
  describe('SkiffRuntimePreferences', () => {
    beforeAll(() => {
      SkiffRuntime.init();
    });

    afterEach(() => {
      Harness.clear();
      SkiffRuntime.setPreference('dom_intersection_observer_enabled', false);
    });

    it('listsPreferences', 0, () => {
      const preferences = SkiffRuntime.preferences();
      expect(preferences.length).assertLarger(100);
      const observer = preference('dom_intersection_observer_enabled');
      expect(observer?.kind).assertEqual('boolean');
      expect(observer?.defaultValue).assertEqual(false);
      expect(observer?.experimental).assertTrue();
      expect(observer?.needsRestart).assertFalse();
      expect(preference('layout_threads')?.kind).assertEqual('integer');
      expect(preference('layout_threads')?.needsRestart).assertTrue();
      expect(preference('network_http_cache_size')?.kind).assertEqual('unsigned');
      expect(typeof preference('user_agent')?.value).assertEqual('string');
      expect(preference('log_filter')).assertUndefined();
      expect(preference('shell_background_color_rgba')).assertUndefined();
      expect(preferences.filter((preference: SkiffPreference) => preference.experimental).length)
        .assertEqual(20);
    });

    it('rejectsInvalidChanges', 0, () => {
      expect(SkiffRuntime.setPreference('no_such_preference', true)).assertContain('Unknown preference');
      expect(SkiffRuntime.setPreference('dom_intersection_observer_enabled', 'yes'))
        .assertContain('takes a boolean');
      expect(SkiffRuntime.setPreference('network_http_cache_size', -1)).assertContain('non-negative');
      expect(SkiffRuntime.setPreference('layout_threads', 1.5)).assertContain('takes an integer');
    });

    it('appliesToPagesLoadedAfterwards', 0, async () => {
      const url = Harness.page('Observer');
      const slot = Harness.show(url);
      await slot.waitFor('pageEnd', url);
      expect(await hasIntersectionObserver(slot)).assertFalse();

      expect(SkiffRuntime.setPreference('dom_intersection_observer_enabled', true)).assertUndefined();
      expect(preference('dom_intersection_observer_enabled')?.value).assertEqual(true);
      slot.mark();
      slot.controller.refresh();
      await slot.waitFor('pageEnd', url);
      expect(await hasIntersectionObserver(slot)).assertTrue();

      expect(SkiffRuntime.setPreference('dom_intersection_observer_enabled', false)).assertUndefined();
      slot.mark();
      slot.controller.refresh();
      await slot.waitFor('pageEnd', url);
      expect(await hasIntersectionObserver(slot)).assertFalse();
    });

    it('servesLicenses', 0, async () => {
      const slot = Harness.show('servo:license');
      await slot.waitFor('pageEnd', 'servo:license');
      expect(slot.controller.getTitle()).assertEqual('Third Party Licenses');
      const text = JSON.parse(await slot.controller.runJavaScript('document.body.innerText')) as string;
      expect(text).assertContain('Mozilla Public License');
      expect(text).assertContain('The FreeType Project');
      // Code in SpiderMonkey, the C++ standard library and data files.
      expect(text).assertContain('The author of this software is David M. Gay.');
      expect(text).assertContain('The LLVM Project is under the Apache License');
      expect(text).assertContain('The Chromium Authors');
      const sections = Number(await slot.controller.runJavaScript(
        '["spidermonkey", "libcxx", "rust-std", "data-files"].filter((id) => document.getElementById(id)).length'));
      expect(sections).assertEqual(4);
    });

    it('reportsVersions', 0, () => {
      expect(/^\d+\.\d+\.\d+$/.test(SkiffRuntime.version)).assertTrue();
      expect(/^\d+\.\d+\.\d+$/.test(SkiffRuntime.servoVersion() ?? '')).assertTrue();
    });
  });
}

/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import { describe, expect, it } from '@ohos/hypium';
import { SkiffRuntime } from '@openharmony-rs/skiff';

export default function runtimeTest() {
  describe('SkiffRuntime', () => {
    it('rejectsUnknownPreference', 0, () => {
      const error = SkiffRuntime.init({ preferences: { 'no_such_preference': true } });
      expect(error).assertContain('Unknown preference no_such_preference');
    });

    it('rejectsPreferenceOfWrongType', 0, () => {
      const error = SkiffRuntime.init({ preferences: { 'dom_geolocation_enabled': 'yes' } });
      expect(error).assertContain('Preference dom_geolocation_enabled takes a boolean');
    });

    it('rejectsInvalidPreferencesJson', 0, () => {
      const error = SkiffRuntime.init({ preferencesJson: '{' });
      expect(error).assertContain('Invalid preferences');
    });

    it('starts', 0, () => {
      expect(SkiffRuntime.init({ preferences: { 'dom_geolocation_enabled': true } })).assertUndefined();
      expect(SkiffRuntime.init()).assertUndefined();
    });
  });
}

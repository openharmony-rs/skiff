/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import bundleManager from '@ohos.bundle.bundleManager';
import { SkiffRuntime } from '@openharmony-rs/skiff';

/** Shows the versions of the app and of Servo, and credits. */
@Component
export struct AboutPage {
  /** Called to show a page in the browser, e.g. `servo:license`. */
  openUrl: (url: string) => void = (url: string) => {};
  private appVersion: string = '';

  aboutToAppear(): void {
    try {
      this.appVersion =
        bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT).versionName;
    } catch (error) {
      this.appVersion = 'unknown';
    }
  }

  @Builder
  paragraph(text: string) {
    Text(text)
      .fontSize(14)
      .width('100%')
  }

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: 12 }) {
          Image($r('app.media.foreground'))
            .width(96)
            .height(96)
          Text($r('app.string.EntryAbility_label'))
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
          Text(`Version ${this.appVersion}`)
            .id('app-version')
            .fontSize(14)
          Text(`Skiff ${SkiffRuntime.version} · Servo ${SkiffRuntime.servoVersion() ?? 'unavailable'}`)
            .id('engine-version')
            .fontSize(14)
            .fontColor(Color.Gray)

          Divider()

          this.paragraph('Shows web pages with Skiff, which uses the Servo web engine instead of ArkWeb.')
          Text('Credits')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .width('100%')
          this.paragraph('Servo is made by the Servo Project Developers and is available under the ' +
            'Mozilla Public License 2.0.')
          // The year is that of the FreeType release in servo's third_party/freetype-sys.
          this.paragraph('Portions of this software are copyright © 2026 The FreeType Project ' +
            '(https://freetype.org). All rights reserved.')
          this.paragraph('This app uses many more open-source components, each under its own license.')

          Button('Open-source licenses')
            .id('open-licenses')
            .onClick(() => {
              this.openUrl('servo:license');
            })
          Button('servo.org', { buttonStyle: ButtonStyleMode.TEXTUAL })
            .onClick(() => {
              this.openUrl('https://servo.org');
            })
        }
        .padding(24)
      }
      .width('100%')
      .height('100%')
    }
    .title('About')
  }
}

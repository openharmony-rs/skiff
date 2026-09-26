/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import common from '@ohos.app.ability.common';
import hilog from '@ohos.hilog';
import {
  OnHistoryChangeEvent,
  OnPageEndEvent,
  OnProgressChangeEvent,
  OnUrlChangeEvent,
  SkiffView,
  SkiffController,
} from '@openharmony-rs/skiff';
import { AboutPage } from './AboutPage';
import { PreferencesPage } from './PreferencesPage';

/** Turns what was typed into the address bar into a URL. */
function toUrl(input: string): string {
  const text = input.trim();
  if (text.includes('://') || ['about:', 'data:', 'servo:'].some((scheme: string) => text.startsWith(scheme))) {
    return text;
  }
  return 'https://' + text;
}

@Entry
@Component
struct Index {
  @StorageProp('initialUrl') initialUrl: string = 'about:blank';
  @StorageProp('showChrome') showChrome: boolean = true;
  @StorageProp('loadUrlRequest') @Watch('onLoadUrlRequest') loadUrlRequest: number = 0;
  @StorageProp('evalScript') evalScript: string = '';
  @State address: string = '';
  @State progress: number = 0;
  @State canGoBack: boolean = false;
  @State canGoForward: boolean = false;
  private controller: SkiffController = new SkiffController();
  private pages: NavPathStack = new NavPathStack();

  onLoadUrlRequest(): void {
    const url = AppStorage.get<string>('loadUrl');
    if (url !== undefined) {
      this.controller.loadUrl(url);
    }
  }

  evaluateScript(event: OnPageEndEvent): void {
    if (this.evalScript.length === 0) {
      return;
    }
    this.controller.runJavaScript(this.evalScript)
      .then((result: string) => {
        hilog.info(0x0000, 'SkiffDemo', 'eval on %{public}s: %{public}s', event.url, result);
      })
      .catch((error: Error) => {
        hilog.error(0x0000, 'SkiffDemo', 'eval on %{public}s failed: %{public}s', event.url, error.message);
      });
  }

  @Builder
  page(name: string) {
    if (name === 'preferences') {
      PreferencesPage()
    } else if (name === 'about') {
      AboutPage({
        openUrl: (url: string) => {
          this.pages.clear();
          this.controller.loadUrl(url);
        },
      })
    }
  }

  onBackPress(): boolean {
    if (this.pages.size() > 0) {
      this.pages.pop();
      return true;
    }
    if (this.controller.closeSoftKeyboard()) {
      return true;
    }
    if (this.controller.accessBackward()) {
      this.controller.backward();
    } else {
      // Exits, unlike going to the background, which shuts Servo down and so saves site data.
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      context.terminateSelf().catch((error: Error) => {
        hilog.error(0x0000, 'SkiffDemo', 'Exiting failed: %{public}s', error.message);
      });
    }
    return true;
  }

  build() {
    Navigation(this.pages) {
      Column() {
        if (this.showChrome) {
          Row({ space: 4 }) {
            Button('◀')
              .enabled(this.canGoBack)
              .onClick(() => {
                this.controller.backward();
              })
            Button('▶')
              .enabled(this.canGoForward)
              .onClick(() => {
                this.controller.forward();
              })
            Button('↻')
              .onClick(() => {
                this.controller.refresh();
              })
            TextInput({ text: this.address, placeholder: 'URL' })
              .type(InputType.URL)
              .enterKeyType(EnterKeyType.Go)
              .layoutWeight(1)
              .onChange((value: string) => {
                this.address = value;
              })
              .onSubmit(() => {
                this.controller.loadUrl(toUrl(this.address));
              })
            Button('⋮')
              .id('menu')
              .bindMenu([
                {
                  value: 'Preferences',
                  action: () => {
                    this.pages.pushPathByName('preferences', null);
                  },
                },
                {
                  value: 'About',
                  action: () => {
                    this.pages.pushPathByName('about', null);
                  },
                },
              ])
          }
          .padding(4)
          .width('100%')

          Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
            .width('100%')
            .visibility(this.progress < 100 ? Visibility.Visible : Visibility.Hidden)
        }

        Stack() {
          SkiffView({
            src: this.initialUrl,
            controller: this.controller,
            onUrlChange: (event: OnUrlChangeEvent) => {
              this.address = event.url;
            },
            onProgressChange: (event: OnProgressChangeEvent) => {
              this.progress = event.newProgress;
            },
            onPageEnd: (event: OnPageEndEvent) => {
              this.evaluateScript(event);
            },
            onHistoryChange: (event: OnHistoryChangeEvent) => {
              this.canGoBack = event.canGoBack;
              this.canGoForward = event.canGoForward;
            },
          })
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .hideToolBar(true)
    .mode(NavigationMode.Stack)
    .navDestination(this.page)
  }
}

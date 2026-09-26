/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import {
  OnAlertEvent,
  OnConsoleEvent,
  OnEngineErrorEvent,
  OnHistoryChangeEvent,
  OnPageBeginEvent,
  OnPageEndEvent,
  OnProgressChangeEvent,
  OnRenderExitedEvent,
  OnTitleReceiveEvent,
  OnUrlChangeEvent,
  SkiffView,
} from '@openharmony-rs/skiff';
import * as Harness from '../Harness';

/** Shows the `SkiffView` of a slot and records its callbacks. */
@Component
struct SlotView {
  slot: Harness.Slot = Harness.slot(0);

  build() {
    SkiffView({
      src: this.slot.src,
      controller: this.slot.controller,
      onPageBegin: (event: OnPageBeginEvent) => this.slot.record('pageBegin', event.url),
      onPageEnd: (event: OnPageEndEvent) => this.slot.record('pageEnd', event.url),
      onProgressChange: (event: OnProgressChangeEvent) => {
        this.slot.record('progress', event.newProgress.toString());
      },
      onTitleReceive: (event: OnTitleReceiveEvent) => this.slot.record('title', event.title),
      onUrlChange: (event: OnUrlChangeEvent) => this.slot.record('url', event.url),
      onHistoryChange: (event: OnHistoryChangeEvent) => {
        this.slot.record('history', `${event.canGoBack},${event.canGoForward}`);
      },
      onConsole: (event: OnConsoleEvent) => this.slot.record('console', `${event.level}:${event.message}`),
      onAlert: (event: OnAlertEvent) => this.slot.record('alert', event.message),
      onRenderExited: (event: OnRenderExitedEvent) => this.slot.record('renderExited', event.reason),
      onEngineError: (event: OnEngineErrorEvent) => this.slot.record('engineError', event.message),
    })
  }
}

/** Shows the slots of `Harness`, one below the other or as tabs. */
@Entry
@Component
struct Index {
  @StorageLink('slotIds') slotIds: number[] = [];
  @StorageLink('tabs') tabs: boolean = false;
  @StorageLink('hiddenTabVisibility') hiddenTabVisibility: Visibility = Visibility.Hidden;
  @StorageLink('activeSlotId') activeSlotId: number = 0;
  @StorageLink('showTextInput') showTextInput: boolean = false;

  onBackPress(): boolean {
    Harness.backPressed();
    return true;
  }

  build() {
    Column() {
      if (this.showTextInput) {
        TextInput({ placeholder: 'ArkUI text field' })
          .id('arkui-input')
          .width('100%')
          .height(56)
      }
      if (this.tabs) {
        Stack() {
          ForEach(this.slotIds, (id: number) => {
            Column() {
              SlotView({ slot: Harness.slot(id) })
            }
            .id('slot-' + id)
            .width('100%')
            .height('100%')
            .visibility(id === this.activeSlotId ? Visibility.Visible : this.hiddenTabVisibility)
          }, (id: number) => id.toString())
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        ForEach(this.slotIds, (id: number) => {
          Column() {
            SlotView({ slot: Harness.slot(id) })
          }
          .id('slot-' + id)
          .width('100%')
          .layoutWeight(1)
        }, (id: number) => id.toString())
      }
    }
    .width('100%')
    .height('100%')
  }
}

/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import common from '@ohos.app.ability.common';
import hilog from '@ohos.hilog';
import { SkiffPreference, SkiffPreferenceValue, SkiffRuntime } from '@openharmony-rs/skiff';
import { fitsKind, StoredPreferences } from '../common/StoredPreferences';

/** A preference as the page shows it. */
interface Entry {
  preference: SkiffPreference;
  /** The value that Servo uses, or for a preference that needs a restart, uses after it. */
  value: SkiffPreferenceValue;
  /** Whether the user changed it from the default. */
  changed: boolean;
  /** Whether it needs a restart, and Servo still uses another value. */
  pending: boolean;
}

/** Lets the user change Servo's preferences, and remembers them for the next start of the app. */
@Component
export struct PreferencesPage {
  @State private entries: Entry[] = [];
  @State private filter: string = '';
  private store: StoredPreferences | undefined = undefined;

  aboutToAppear(): void {
    this.store = new StoredPreferences(this.getUIContext().getHostContext() as common.Context);
    this.refresh();
  }

  private refresh(): void {
    const store = this.store;
    if (store === undefined) {
      return;
    }
    this.entries = SkiffRuntime.preferences().map((preference: SkiffPreference): Entry => {
      const stored = store.get(preference.name);
      const value = preference.needsRestart ? (stored ?? preference.defaultValue) : preference.value;
      return {
        preference: preference,
        value: value,
        changed: stored !== undefined,
        pending: preference.needsRestart && value !== preference.value,
      };
    });
  }

  /** Changes the preference, right away unless it needs a restart, and remembers it. */
  private change(preference: SkiffPreference, value: SkiffPreferenceValue): void {
    if (!preference.needsRestart) {
      const error = SkiffRuntime.setPreference(preference.name, value);
      if (error !== undefined) {
        this.toast(error);
        return;
      }
    }
    if (value === preference.defaultValue) {
      this.store?.remove(preference.name);
    } else {
      this.store?.set(preference.name, value);
    }
  }

  private submit(entry: Entry, text: string): void {
    const kind = entry.preference.kind;
    const value: SkiffPreferenceValue = kind === 'string' ? text : Number(text.trim());
    if (kind !== 'string' && (text.trim().length === 0 || !fitsKind(kind, value))) {
      this.toast(kind === 'unsigned' ? 'Enter a whole number of 0 or more' : 'Enter a whole number');
    } else if (value !== entry.value) {
      this.change(entry.preference, value);
    }
    this.refresh();
  }

  private experimental(): Entry[] {
    return this.entries.filter((entry: Entry) => entry.preference.experimental);
  }

  private experimentalEnabled(): boolean {
    const entries = this.experimental();
    return entries.length > 0 && entries.every((entry: Entry) => entry.value === true);
  }

  private setExperimental(enabled: boolean): void {
    this.experimental().forEach((entry: Entry) => {
      this.change(entry.preference, enabled ? true : entry.preference.defaultValue);
    });
    this.refresh();
  }

  private shown(needsRestart: boolean): Entry[] {
    const filter = this.filter.trim().toLowerCase().replace(/\s+/g, '_');
    return this.entries.filter((entry: Entry) =>
      entry.preference.needsRestart === needsRestart && entry.preference.name.includes(filter));
  }

  private restart(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    // Saves cookies and other site data, which the restart would lose.
    SkiffRuntime.shutdown();
    try {
      context.getApplicationContext().restartApp({
        bundleName: context.abilityInfo.bundleName,
        abilityName: context.abilityInfo.name,
      });
    } catch (error) {
      this.toast(`Restarting failed, start the app again: ${(error as Error).message}`);
    }
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (error) {
      hilog.error(0x0000, 'SkiffDemo', '%{public}s', message);
    }
  }

  @Builder
  row(entry: Entry) {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        Text(entry.preference.name)
          .fontSize(14)
          .fontWeight(entry.changed ? FontWeight.Bold : FontWeight.Normal)
          .layoutWeight(1)
        if (entry.preference.kind === 'boolean') {
          Toggle({ type: ToggleType.Switch, isOn: entry.value === true })
            .id('preference-' + entry.preference.name)
            .onChange((isOn: boolean) => {
              if (isOn !== (entry.value === true)) {
                this.change(entry.preference, isOn);
                this.refresh();
              }
            })
        }
      }
      .width('100%')

      if (entry.preference.kind !== 'boolean') {
        TextInput({ text: entry.value.toString() })
          .id('preference-' + entry.preference.name)
          .enterKeyType(EnterKeyType.Done)
          .onSubmit((enterKey: EnterKeyType, event: SubmitEvent) => {
            this.submit(entry, event.text);
          })
      }
      if (entry.changed || entry.pending) {
        Row({ space: 8 }) {
          Text(entry.pending ? 'Takes effect after a restart' : '')
            .fontSize(12)
            .fontColor(Color.Gray)
            .layoutWeight(1)
          if (entry.changed) {
            Button('Reset')
              .fontSize(12)
              .height(28)
              .onClick(() => {
                this.change(entry.preference, entry.preference.defaultValue);
                this.refresh();
              })
          }
        }
        .width('100%')
      }
    }
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
  }

  @Builder
  list(needsRestart: boolean) {
    List() {
      ForEach(this.shown(needsRestart), (entry: Entry) => {
        ListItem() {
          this.row(entry)
        }
      }, (entry: Entry) => `${entry.preference.name}=${JSON.stringify(entry.value)},${entry.changed}`)
    }
    .divider({ strokeWidth: 1, color: '#1F000000' })
    .width('100%')
    .layoutWeight(1)
  }

  build() {
    NavDestination() {
      Column() {
        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text('Experimental web platform features')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
            Text('Turns on features that are still in development, for the pages loaded afterwards.')
              .fontSize(12)
              .fontColor(Color.Gray)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.experimentalEnabled() })
            .id('experimental')
            .onChange((isOn: boolean) => {
              if (isOn !== this.experimentalEnabled()) {
                this.setExperimental(isOn);
              }
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })

        Search({ value: this.filter, placeholder: 'Search' })
          .margin({ left: 16, right: 16 })
          .onChange((value: string) => {
            this.filter = value;
          })

        Tabs() {
          TabContent() {
            this.list(false)
          }
          .tabBar(`Live (${this.shown(false).length})`)

          TabContent() {
            Column() {
              Row({ space: 8 }) {
                Text('Changes to these apply when the app starts again.')
                  .fontSize(12)
                  .layoutWeight(1)
                Button('Restart now')
                  .enabled(this.entries.some((entry: Entry) => entry.pending))
                  .onClick(() => {
                    this.restart();
                  })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })

              this.list(true)
            }
          }
          .tabBar(`After restart (${this.shown(true).length})`)
        }
        .layoutWeight(1)
      }
    }
    .title('Preferences')
  }
}

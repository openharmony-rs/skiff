/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import { window } from '@kit.ArkUI';
import { SkiffController } from '@openharmony-rs/skiff';

/** A callback of `SkiffView` that was called. */
export interface SlotEvent {
  /** The name of the callback without `on`, e.g. `pageEnd`. */
  kind: string;
  /** The URL, title, message or other argument, `history` events have `<canGoBack>,<canGoForward>`. */
  value: string;
}

/** A `SkiffView` in the test page, and the callbacks it called. */
export class Slot {
  readonly id: number;
  readonly src: string;
  readonly controller: SkiffController;
  readonly events: SlotEvent[] = [];
  /** The index of the first event that `waitFor` looks at. */
  private start: number = 0;

  constructor(id: number, src: string, controller: SkiffController) {
    this.id = id;
    this.src = src;
    this.controller = controller;
  }

  record(kind: string, value: string): void {
    this.events.push({ kind: kind, value: value });
  }

  /** Makes `waitFor` ignore the events so far. */
  mark(): void {
    this.start = this.events.length;
  }

  /** Waits for an event of the kind, and with the value if given, since the last `mark`. */
  async waitFor(kind: string, value?: string, timeoutMs: number = 10000): Promise<SlotEvent> {
    const deadline = Date.now() + timeoutMs;
    while (true) {
      const event = this.events.slice(this.start).find((event: SlotEvent) =>
        event.kind === kind && (value === undefined || event.value === value));
      if (event !== undefined) {
        return event;
      }
      if (Date.now() > deadline) {
        throw new Error(`No ${kind} event ${value ?? ''} within ${timeoutMs} ms, got ` +
          JSON.stringify(this.events.slice(this.start)));
      }
      await sleep(20);
    }
  }

  /** The values of the events of the kind since the last `mark`. */
  values(kind: string): string[] {
    return this.events.slice(this.start).filter((event: SlotEvent) => event.kind === kind)
      .map((event: SlotEvent) => event.value);
  }

  /** The kinds of the events since the last `mark`. */
  kinds(): string[] {
    return this.events.slice(this.start).map((event: SlotEvent) => event.kind);
  }
}

const SLOT_IDS = 'slotIds';
const TABS = 'tabs';
const HIDDEN_TAB_VISIBILITY = 'hiddenTabVisibility';
const ACTIVE_SLOT_ID = 'activeSlotId';
const SHOW_TEXT_INPUT = 'showTextInput';
const slots: Map<number, Slot> = new Map();
let lastSlotId = 0;
const backPresses: boolean[] = [];
let mainWindow: window.Window | undefined = undefined;

/**
 * Shows a `SkiffView` that loads `src` below the ones shown already, or, with tabs, as the active
 * tab.
 */
export function show(src: string, controller?: SkiffController): Slot {
  lastSlotId++;
  const slot = new Slot(lastSlotId, src, controller ?? new SkiffController());
  slots.set(slot.id, slot);
  AppStorage.setOrCreate<number>(ACTIVE_SLOT_ID, slot.id);
  AppStorage.setOrCreate<number[]>(SLOT_IDS, Array.from(slots.keys()));
  return slot;
}

/** Removes the `SkiffView` of the slot from the page. With tabs, the last one becomes active. */
export function remove(slot: Slot): void {
  slots.delete(slot.id);
  const ids = Array.from(slots.keys());
  if (AppStorage.get<number>(ACTIVE_SLOT_ID) === slot.id) {
    AppStorage.setOrCreate<number>(ACTIVE_SLOT_ID, ids.length > 0 ? ids[ids.length - 1] : 0);
  }
  AppStorage.setOrCreate<number[]>(SLOT_IDS, ids);
}

/**
 * Shows the slots as tabs from now on: on top of each other, with only the active one visible and
 * the others set to `hidden`. Call it while no slot is shown.
 */
export function useTabs(hidden: Visibility): void {
  AppStorage.setOrCreate<Visibility>(HIDDEN_TAB_VISIBILITY, hidden);
  AppStorage.setOrCreate<boolean>(TABS, true);
}

/** Makes the tab of the slot the visible one. */
export function activate(slot: Slot): void {
  AppStorage.setOrCreate<number>(ACTIVE_SLOT_ID, slot.id);
}

/** Shows an ArkUI text field with the id `arkui-input` above the slots. */
export function showTextInput(): void {
  AppStorage.setOrCreate<boolean>(SHOW_TEXT_INPUT, true);
}

/** Removes all `SkiffView` components and the text field, stops using tabs, forgets back presses. */
export function clear(): void {
  slots.clear();
  backPresses.length = 0;
  AppStorage.setOrCreate<number[]>(SLOT_IDS, []);
  AppStorage.setOrCreate<number>(ACTIVE_SLOT_ID, 0);
  AppStorage.setOrCreate<boolean>(TABS, false);
  AppStorage.setOrCreate<boolean>(SHOW_TEXT_INPUT, false);
}

/** Called by `TestAbility` with the window of the test page. */
export function setMainWindow(pageWindow: window.Window): void {
  mainWindow = pageWindow;
}

/** The height of the soft keyboard in pixels, 0 while it is hidden. */
export function keyboardHeight(): number {
  try {
    return mainWindow?.getWindowAvoidArea(window.AvoidAreaType.TYPE_KEYBOARD).bottomRect.height ?? 0;
  } catch (error) {
    throw new Error(`Getting the area of the soft keyboard failed: ${(error as Error).message}`);
  }
}

export function slot(id: number): Slot {
  return slots.get(id) ?? new Slot(id, 'about:blank', new SkiffController());
}

/** Handles the back key like an app should, and records whether a soft keyboard was closed. */
export function backPressed(): void {
  let closed = false;
  slots.forEach((shown: Slot) => {
    closed = shown.controller.closeSoftKeyboard() || closed;
  });
  backPresses.push(closed);
}

/** For each back press, whether it closed a soft keyboard. */
export function backPressResults(): boolean[] {
  return backPresses.slice();
}

export function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => setTimeout(resolve, ms));
}

/** Waits until `condition` holds. */
export async function waitUntil(condition: () => Promise<boolean>, what: string,
  timeoutMs: number = 10000): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (!(await condition())) {
    if (Date.now() > deadline) {
      throw new Error(`Timed out after ${timeoutMs} ms waiting for ${what}`);
    }
    await sleep(50);
  }
}

/** A `data:` URL of an HTML document. */
export function page(title: string, body: string = ''): string {
  return 'data:text/html;charset=utf-8,' + encodeURIComponent(`<!DOCTYPE html><title>${title}</title>${body}`);
}

/** A page whose background changes colour with every animation frame, which it counts. */
export function animationPage(title: string): string {
  return page(title, `<body style="margin:0"><script>
    window.frameCount = 0;
    function tick(now) {
      window.frameCount++;
      document.body.style.background = 'hsl(' + Math.round(now / 4) % 360 + ', 100%, 50%)';
      requestAnimationFrame(tick);
    }
    requestAnimationFrame(tick);
    </script>`);
}

/** The number of frames that a page of `animationPage` counted. */
export async function frameCount(slot: Slot): Promise<number> {
  return Number(await slot.controller.runJavaScript('window.frameCount'));
}

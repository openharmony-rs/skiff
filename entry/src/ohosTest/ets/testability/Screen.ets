/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import { image } from '@kit.ImageKit';
import { abilityDelegatorRegistry, Driver, ON, Rect } from '@kit.TestKit';
import * as Harness from './Harness';

export interface Point {
  x: number;
  y: number;
}

// Colours for checks against screenshots. Each looks the same in RGBA and BGRA.
export const GREEN = [0, 255, 0];
export const MAGENTA = [255, 0, 255];
export const GRAY = [128, 128, 128];

/** The bounds of the slot on the screen, in pixels. */
export async function bounds(driver: Driver, slot: Harness.Slot): Promise<Rect> {
  try {
    const component = await driver.waitForComponent(ON.id('slot-' + slot.id), 5000);
    return await component.getBounds();
  } catch (error) {
    throw new Error(`Getting the bounds of slot ${slot.id} failed: ${(error as Error).message}`);
  }
}

/** The point at the given fractions of the width and height of the bounds. */
export function pointIn(rect: Rect, x: number = 0.5, y: number = 0.5): Point {
  return {
    x: Math.round(rect.left + (rect.right - rect.left) * x),
    y: Math.round(rect.top + (rect.bottom - rect.top) * y),
  };
}

/** The colours of the screen at the points, as `[red, green, blue]`, from one screenshot. */
export async function colorsAt(driver: Driver, points: Point[]): Promise<number[][]> {
  const path = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().cacheDir + '/screen.png';
  try {
    if (!(await driver.screenCap(path))) {
      throw new Error('the driver could not save it');
    }
  } catch (error) {
    throw new Error(`Taking a screenshot failed: ${(error as Error).message}`);
  }
  const source = image.createImageSource(path);
  const pixelMap = await source.createPixelMap();
  const colors: number[][] = [];
  for (const point of points) {
    const area: image.PositionArea = {
      pixels: new ArrayBuffer(4),
      offset: 0,
      stride: 4,
      region: { size: { width: 1, height: 1 }, x: point.x, y: point.y },
    };
    await pixelMap.readPixels(area);
    const pixel = new Uint8Array(area.pixels);
    colors.push([pixel[0], pixel[1], pixel[2]]);
  }
  await pixelMap.release();
  await source.release();
  return colors;
}

export function isColor(pixel: number[], color: number[]): boolean {
  return color.every((value: number, index: number) => Math.abs(pixel[index] - value) < 40);
}

/** Waits until the screen has the colour at the point. */
export async function waitForColor(driver: Driver, point: Point, color: number[],
  what: string): Promise<void> {
  let last: number[] = [];
  try {
    await Harness.waitUntil(async () => {
      last = (await colorsAt(driver, [point]))[0];
      return isColor(last, color);
    }, what);
  } catch (error) {
    throw new Error(`${(error as Error).message}, the screen showed ${JSON.stringify(last)}`);
  }
}

/** Waits until the screen shows three colours in a row at the point, as an animation does. */
export async function waitForAnimation(driver: Driver, point: Point, what: string): Promise<void> {
  const colors: string[] = [];
  await Harness.waitUntil(async () => {
    colors.push((await colorsAt(driver, [point]))[0].join());
    return new Set<string>(colors.slice(-3)).size === 3;
  }, `${what} to animate on the screen`);
}

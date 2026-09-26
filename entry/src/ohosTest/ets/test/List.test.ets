/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import apiTest from './Api.test';
import demoAppTest from './DemoApp.test';
import inputTest from './Input.test';
import javaScriptTest from './JavaScript.test';
import lifecycleTest from './Lifecycle.test';
import preferencesTest from './Preferences.test';
import renderingTest from './Rendering.test';
import runtimeTest from './Runtime.test';
import shutdownTest from './Shutdown.test';
import tabsTest from './Tabs.test';
import viewportTest from './Viewport.test';

/**
 * All suites. They share one Servo, so the order matters: `SkiffRuntime` has to run before
 * anything starts Servo, `DemoApp` just before `SkiffRuntimeShutdown`, and that one last.
 */
export default function testsuite() {
  runtimeTest();
  apiTest();
  preferencesTest();
  javaScriptTest();
  viewportTest();
  lifecycleTest();
  renderingTest();
  tabsTest();
  inputTest();
  demoAppTest();
  shutdownTest();
}

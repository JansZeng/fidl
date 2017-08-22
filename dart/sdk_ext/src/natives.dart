// Copyright 2016 The Fuchsia Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

part of internal;

class MxTime {
  static int _get(int clockId) native "MxTime_Get";

  // Clock ID zero is MX_CLOCK_MONOTONIC.
  static int timerMillisecondClock() => _get(0) ~/ (1000 * 1000);
}

Handle _environment;
Handle _outgoingServices;

class MxStartupInfo {
  static Handle takeEnvironment() {
    Handle handle = _environment;
    _environment = null;
    return handle;
  }

  static Handle takeOutgoingServices() {
    Handle handle = _outgoingServices;
    _outgoingServices = null;
    return handle;
  }
}

// Copyright 2016 The Fuchsia Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef LIB_FIDL_DART_SDK_EXT_SRC_HANDLE_WAITER_H_
#define LIB_FIDL_DART_SDK_EXT_SRC_HANDLE_WAITER_H_

#include <mx/handle.h>

#include <mutex>

#include "lib/fidl/c/waiter/async_waiter.h"
#include "lib/tonic/dart_wrappable.h"

namespace tonic {
class DartLibraryNatives;
}  // namespace tonic

namespace fidl {
namespace dart {

class Handle;

class HandleWaiter : public ftl::RefCountedThreadSafe<HandleWaiter>,
                     public tonic::DartWrappable {
  DEFINE_WRAPPERTYPEINFO();
  FRIEND_REF_COUNTED_THREAD_SAFE(HandleWaiter);
  FRIEND_MAKE_REF_COUNTED(HandleWaiter);

 public:
  static ftl::RefPtr<HandleWaiter> Create(Handle* handle,
                                          mx_signals_t signals,
                                          mx_time_t timeout,
                                          Dart_Handle callback);

  void Cancel();

  bool is_valid() const { return wait_id_ != 0; }

  static void RegisterNatives(tonic::DartLibraryNatives* natives);

 private:
  explicit HandleWaiter(Handle* handle,
                        mx_signals_t signals,
                        mx_time_t timeout,
                        Dart_Handle callback);
  ~HandleWaiter();

  void OnWaitComplete(mx_status_t status, mx_signals_t pending);
  static void CallOnWaitComplete(mx_status_t status,
                                 mx_signals_t pending,
                                 uint64_t count,
                                 void* closure);

  const FidlAsyncWaiter* waiter_;
  Handle* handle_;
  tonic::DartPersistentValue callback_;
  FidlAsyncWaitID wait_id_ = 0;
};

}  // namespace dart
}  // namespace fidl

#endif  // LIB_FIDL_DART_SDK_EXT_SRC_HANDLE_WAITER_H_

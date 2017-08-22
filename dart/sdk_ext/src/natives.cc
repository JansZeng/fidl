// Copyright 2016 The Fuchsia Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "lib/fidl/dart/sdk_ext/src/natives.h"

#include <magenta/syscalls.h>

#include <stdio.h>
#include <string.h>

#include <memory>
#include <vector>

#include "dart/runtime/include/dart_api.h"
#include "lib/fidl/dart/sdk_ext/src/handle.h"
#include "lib/fidl/dart/sdk_ext/src/handle_waiter.h"
#include "lib/fidl/dart/sdk_ext/src/system.h"
#include "lib/ftl/arraysize.h"
#include "lib/ftl/logging.h"
#include "lib/ftl/macros.h"
#include "lib/tonic/dart_binding_macros.h"
#include "lib/tonic/dart_class_library.h"
#include "lib/tonic/dart_class_provider.h"
#include "lib/tonic/dart_library_natives.h"
#include "lib/tonic/logging/dart_invoke.h"
#include "lib/tonic/typed_data/uint8_list.h"

using tonic::ToDart;

namespace fidl {
namespace dart {
namespace {

static tonic::DartLibraryNatives* g_natives;

tonic::DartLibraryNatives* InitNatives() {
  tonic::DartLibraryNatives* natives = new tonic::DartLibraryNatives();
  HandleWaiter::RegisterNatives(natives);
  Handle::RegisterNatives(natives);
  System::RegisterNatives(natives);

  return natives;
}

}  // namespace

void Initialize() {
  auto dart_state = tonic::DartState::Current();
  std::unique_ptr<tonic::DartClassProvider> fidl_class_provider(
      new tonic::DartClassProvider(dart_state, "dart:fidl.internal"));
  dart_state->class_library().add_provider("fidl.internal",
                                           std::move(fidl_class_provider));
}

#define REGISTER_FUNCTION(name, count) \
  { "" #name, name, count }            \
  ,
#define DECLARE_FUNCTION(name, count) \
  extern void name(Dart_NativeArguments args);

#define FIDL_NATIVE_LIST(V)    \
  V(MxTime_Get, 1)

FIDL_NATIVE_LIST(DECLARE_FUNCTION);

static struct NativeEntries {
  const char* name;
  Dart_NativeFunction function;
  int argument_count;
} Entries[] = {FIDL_NATIVE_LIST(REGISTER_FUNCTION)};

Dart_NativeFunction NativeLookup(Dart_Handle name,
                                 int argument_count,
                                 bool* auto_setup_scope) {
  const char* function_name = nullptr;
  Dart_Handle result = Dart_StringToCString(name, &function_name);
  DART_CHECK_VALID(result);
  assert(function_name != nullptr);
  assert(auto_setup_scope != nullptr);
  *auto_setup_scope = true;
  size_t num_entries = arraysize(Entries);
  for (size_t i = 0; i < num_entries; ++i) {
    const struct NativeEntries& entry = Entries[i];
    if (!strcmp(function_name, entry.name) &&
        (entry.argument_count == argument_count)) {
      return entry.function;
    }
  }
  if (!g_natives)
    g_natives = InitNatives();
  return g_natives->GetNativeFunction(name, argument_count, auto_setup_scope);
}

const uint8_t* NativeSymbol(Dart_NativeFunction native_function) {
  size_t num_entries = arraysize(Entries);
  for (size_t i = 0; i < num_entries; ++i) {
    const struct NativeEntries& entry = Entries[i];
    if (entry.function == native_function) {
      return reinterpret_cast<const uint8_t*>(entry.name);
    }
  }
  if (!g_natives)
    g_natives = InitNatives();
  return g_natives->GetSymbol(native_function);
}

static void SetInvalidArgumentReturn(Dart_NativeArguments arguments) {
  Dart_SetIntegerReturnValue(arguments,
                             static_cast<int64_t>(MX_ERR_INVALID_ARGS));
}

#define CHECK_INTEGER_ARGUMENT(num, result, failure)                  \
  {                                                                   \
    Dart_Handle __status;                                             \
    __status = Dart_GetNativeIntegerArgument(arguments, num, result); \
    if (Dart_IsError(__status)) {                                     \
      Set##failure##Return(arguments);                                \
      return;                                                         \
    }                                                                 \
  }

void MxTime_Get(Dart_NativeArguments arguments) {
  int64_t clock_id;
  CHECK_INTEGER_ARGUMENT(0, &clock_id, InvalidArgument);

  mx_time_t time = mx_time_get(clock_id);
  Dart_SetIntegerReturnValue(arguments, static_cast<int64_t>(time));
}

}  // namespace dart
}  // namespace fidl

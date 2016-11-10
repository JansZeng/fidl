// Copyright 2016 The Fuchsia Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

part of bindings;

abstract class Union { // ignore: one_member_abstracts
  void encode(Encoder encoder, int offset);
}

class UnionError {}

class UnsetUnionTagError extends UnionError {
  final curTag;
  final requestedTag;

  UnsetUnionTagError(this.curTag, this.requestedTag);

  String toString() {
    return "Tried to read unset union member: $requestedTag "
        "current member: $curTag.";
  }
}

// Copyright 2014 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

part of core;

class ChannelReadResult {
  final int status;
  final int bytesRead;
  final int handlesRead;

  ChannelReadResult(this.status, this.bytesRead, this.handlesRead);
  ChannelReadResult.fromList(List<int> resultList)
      : this(resultList[0], resultList[1], resultList[2]);

  String toString() {
    return "ChannelReadResult("
        "status: ${getStringForStatus(status)}, bytesRead: $bytesRead, "
        "handlesRead: $handlesRead)";
  }
}

class ChannelQueryAndReadState {
  static final List _result = new List(5);

  List<Handle> _handles;

  int get status => _result[0];
  ByteData get data => _result[1];
  List<Handle> get handles => _handles;
  int get dataLength => _result[3];
  int get handlesLength => _result[4];

  ChannelQueryAndReadState();

  void queryAndRead(Handle handle, int flags) {
    MxChannel.queryAndRead(handle.h, flags, _result);

    if (handlesLength == 0) {
      _handles = null;
    } else {
      _handles = new List(handlesLength);
      for (int i = 0; i < handlesLength; i++) {
        _handles[i] = new Handle(_result[2][i]);
      }
    }
  }

  String toString() {
    return "ChannelQueryAndReadState("
        "status: ${getStringForStatus(status)}, dataLength: $dataLength, "
        "handlesLength: $handlesLength)";
  }
}

class Channel {
  static const int WRITE_FLAG_NONE = 0;
  static const int READ_FLAG_NONE = 0;
  static const int READ_FLAG_MAY_DISCARD = 1 << 0;

  static final _queryAndReadState = new ChannelQueryAndReadState();

  Handle handle;
  int status;

  Channel(this.handle);

  bool get ok => status == NO_ERROR;

  int write(ByteData data,
      [int numBytes = -1, List<Handle> handles = null, int flags = 0]) {
    if (handle == null) {
      status = ERR_INVALID_ARGS;
      return status;
    }

    int dataLengthInBytes = (data == null) ? 0 : data.lengthInBytes;

    // If numBytes has the default value, use the full length of the data.
    int dataNumBytes = (numBytes == -1) ? dataLengthInBytes : numBytes;
    if (dataNumBytes > dataLengthInBytes) {
      status = ERR_INVALID_ARGS;
      return status;
    }

    // handles may be null, otherwise convert to ints.
    List mojoHandles;
    if (handles != null) {
      mojoHandles = new List(handles.length);
      for (int i = 0; i < handles.length; i++) {
        mojoHandles[i] = handles[i].h;
      }
    }

    // Do the call.
    status = MxChannel.write(
        handle.h, data, dataNumBytes, mojoHandles, flags);
    return status;
  }

  ChannelReadResult read(ByteData data,
      [int numBytes = -1, List<Handle> handles = null, int flags = 0]) {
    if (handle == null) {
      status = ERR_INVALID_ARGS;
      return null;
    }

    // If numBytes has the default value, use the full length of the data.
    int dataNumBytes;
    if (data == null) {
      dataNumBytes = 0;
    } else {
      dataNumBytes = (numBytes == -1) ? data.lengthInBytes : numBytes;
      if (dataNumBytes > data.lengthInBytes) {
        status = ERR_INVALID_ARGS;
        return null;
      }
    }

    // handles may be null, otherwise make an int list for the handles.
    List<int> mojoHandles;
    if (handles == null) {
      mojoHandles = null;
    } else {
      mojoHandles = new List<int>(handles.length);
    }

    // Do the call.
    List result = MxChannel.read(
        handle.h, data, dataNumBytes, mojoHandles, flags);

    if (result == null) {
      status = ERR_INVALID_ARGS;
      return null;
    }

    assert((result is List) && (result.length == 3));
    var readResult = new ChannelReadResult.fromList(result);

    // Copy out the handles that were read.
    if (handles != null) {
      for (var i = 0; i < readResult.handlesRead; i++) {
        handles[i] = new Handle(mojoHandles[i]);
      }
    }

    status = readResult.status;
    return readResult;
  }

  ChannelReadResult query() => read(null);

  bool setDescription(String description) =>
      MxHandle.setDescription(handle.h, description);

  /// Warning: The object returned by this function, and the buffers inside of
  /// it are only valid until the next call to this function by the same
  /// isolate.
  ChannelQueryAndReadState queryAndRead([int flags = 0]) {
    if (handle == null) {
      status = ERR_INVALID_ARGS;
      return null;
    }

    _queryAndReadState.queryAndRead(handle, flags);
    status = _queryAndReadState.status;
    return _queryAndReadState;
  }

  void close() {
    handle.close();
    handle = null;
  }

  String toString() => "Channel(handle: $handle, "
      "status: ${getStringForStatus(status)})";
}

class ChannelPair {
  List<Channel> channels;
  int status;

  ChannelPair._() : status = NO_ERROR;

  factory ChannelPair() {
    List result = MxChannel.create(0);
    if (result == null) {
      return null;
    }
    assert((result is List) && (result.length == 3));

    Handle end1 = new Handle(result[1]);
    Handle end2 = new Handle(result[2]);
    ChannelPair pipe = new ChannelPair._();
    pipe.channels = new List(2);
    pipe.channels[0] = new Channel(end1);
    pipe.channels[1] = new Channel(end2);
    pipe.status = result[0];
    return pipe;
  }
}

// Copyright 2016 The Fuchsia Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

part of bindings;

int _align(int size) =>
    size + ((kAlignment - (size & kAlignmentMask)) & kAlignmentMask);

const int kAlignment = 8;
const int kAlignmentMask = 0x7;
const int kAlignmentShift = 3;
const int kSerializedHandleSize = 4;
const int kSerializedInterfaceSize = 8; // 4-byte handle + 4-byte version
const int kPointerSize = 8;
const int kUnionSize = 16;
const int kEnumSize = 4;
const StructDataHeader kMapStructHeader = const StructDataHeader(24, 0);
const int kUnspecifiedArrayLength = -1;
const int kNothingNullable = 0;
const int kArrayNullable = 1;
const int kElementNullable = 2;

bool isArrayNullable(int nullability) => (nullability & kArrayNullable) > 0;
bool isElementNullable(int nullability) => (nullability & kElementNullable) > 0;

class StructDataHeader {
  static const int kHeaderSize = 8;
  static const int kSizeOffset = 0;
  static const int kVersionOffset = 4;
  final int size;
  final int version;

  const StructDataHeader(this.size, this.version);

  @override
  String toString() => "StructDataHeader($size, $version)";
}

class ArrayDataHeader {
  static const int kHeaderSize = 8;
  static const int kSizeOffset = 0;
  static const int kNumElementsOffset = 4;
  final int size;
  final int numElements;

  const ArrayDataHeader(this.size, this.numElements);

  @override
  String toString() => "ArrayDataHeader($size, $numElements)";
}

class FidlCodecError extends Error {
  String message;
  FidlCodecError(this.message) : super();

  @override
  String toString() => message;
}

class _EncoderBuffer {
  ByteData buffer;
  List<core.Handle> handles;
  int extent;

  static const int kInitialBufferSize = 1024;

  _EncoderBuffer([int size = -1])
      : buffer = new ByteData(size > 0 ? size : kInitialBufferSize),
        handles = [],
        extent = 0;

  void _grow(int newSize) {
    Uint32List newBuffer = new Uint32List((newSize >> 2) + 1);
    int idx = 0;
    for (int i = 0; i < buffer.lengthInBytes; i += 4) {
      newBuffer[idx] = buffer.getUint32(i, Endianness.LITTLE_ENDIAN);
      idx++;
    }
    buffer = newBuffer.buffer.asByteData();
  }

  void claimMemory(int claimSize) {
    extent += claimSize;
    if (extent > buffer.lengthInBytes) {
      int newSize = buffer.lengthInBytes + claimSize;
      newSize += (newSize >> 1);
      _grow(newSize);
    }
  }

  ByteData get trimmed => new ByteData.view(buffer.buffer, 0, extent);
}

class Encoder {
  _EncoderBuffer _buffer;
  int _base;

  Encoder([int size = -1])
      : _buffer = new _EncoderBuffer(size),
        _base = 0;

  Encoder._fromBuffer(_EncoderBuffer buffer)
      : _buffer = buffer,
        _base = buffer.extent;

  Encoder getStructEncoderAtOffset(StructDataHeader dataHeader) {
    var result = new Encoder._fromBuffer(_buffer);
    result.encodeStructDataHeader(dataHeader);
    return result;
  }

  Encoder getArrayEncoderAtOffset(ArrayDataHeader dataHeader) {
    var result = new Encoder._fromBuffer(_buffer);
    result.encodeArrayDataHeader(dataHeader);
    return result;
  }

  Message get message => new Message(
      _buffer.trimmed, _buffer.handles, _buffer.extent, _buffer.handles.length);

  void encodeStructDataHeader(StructDataHeader dataHeader) {
    _buffer.claimMemory(_align(dataHeader.size));
    encodeUint32(dataHeader.size, StructDataHeader.kSizeOffset);
    encodeUint32(dataHeader.version, StructDataHeader.kVersionOffset);
  }

  void encodeArrayDataHeader(ArrayDataHeader dataHeader) {
    _buffer.claimMemory(_align(dataHeader.size));
    encodeUint32(dataHeader.size, ArrayDataHeader.kSizeOffset);
    encodeUint32(dataHeader.numElements, ArrayDataHeader.kNumElementsOffset);
  }

  static const String kErrorUnsigned =
      'Passing negative value to unsigned encoder';

  void encodeBool(bool value, int offset, int bit) {
    if (value) {
      int encodedValue = _buffer.buffer.getUint8(_base + offset);
      encodedValue |= (1 << bit);
      _buffer.buffer.setUint8(_base + offset, encodedValue);
    }
  }

  void encodeInt8(int value, int offset) =>
      _buffer.buffer.setInt8(_base + offset, value);

  void encodeUint8(int value, int offset) {
    if (value < 0) {
      throw new FidlCodecError('$kErrorUnsigned: $value');
    }
    _buffer.buffer.setUint8(_base + offset, value);
  }

  void encodeInt16(int value, int offset) =>
      _buffer.buffer.setInt16(_base + offset, value, Endianness.LITTLE_ENDIAN);

  void encodeUint16(int value, int offset) {
    if (value < 0) {
      throw new FidlCodecError('$kErrorUnsigned: $value');
    }
    _buffer.buffer.setUint16(_base + offset, value, Endianness.LITTLE_ENDIAN);
  }

  void encodeInt32(int value, int offset) =>
      _buffer.buffer.setInt32(_base + offset, value, Endianness.LITTLE_ENDIAN);

  void encodeUint32(int value, int offset) {
    if (value < 0) {
      throw new FidlCodecError('$kErrorUnsigned: $value');
    }
    _buffer.buffer.setUint32(_base + offset, value, Endianness.LITTLE_ENDIAN);
  }

  void encodeInt64(int value, int offset) =>
      _buffer.buffer.setInt64(_base + offset, value, Endianness.LITTLE_ENDIAN);

  void encodeUint64(int value, int offset) {
    if (value < 0) {
      throw new FidlCodecError('$kErrorUnsigned: $value');
    }
    _buffer.buffer.setUint64(_base + offset, value, Endianness.LITTLE_ENDIAN);
  }

  void encodeFloat(double value, int offset) => _buffer.buffer
      .setFloat32(_base + offset, value, Endianness.LITTLE_ENDIAN);

  void encodeDouble(double value, int offset) => _buffer.buffer
      .setFloat64(_base + offset, value, Endianness.LITTLE_ENDIAN);

  void encodeHandle(core.Handle value, int offset, bool nullable) {
    if ((value == null) || !value.isValid) {
      encodeInvalidHandle(offset, nullable);
    } else {
      encodeUint32(_buffer.handles.length, offset);
      _buffer.handles.add(value);
    }
  }

  void encodeChannel(core.Channel value, int offset, bool nullable) =>
    encodeHandle(value != null ? value.handle : null, offset, nullable);

  void encodeInterfaceHandle(
      InterfaceHandle interfaceHandle, int offset, bool nullable) {
    if (interfaceHandle == null) {
      encodeInvalidHandle(offset, nullable);
      // Set the version field to 0.
      encodeUint32(0, offset + kSerializedHandleSize);
    } else {
      encodeChannel(interfaceHandle.passChannel(), offset, nullable);
      encodeUint32(interfaceHandle.version, offset + kSerializedHandleSize);
    }
  }

  void encodeInterfaceRequest(
      InterfaceRequest interfaceRequest, int offset, bool nullable) {
    if (interfaceRequest == null) {
      encodeInvalidHandle(offset, nullable);
    } else {
      encodeChannel(interfaceRequest.passChannel(), offset, nullable);
    }
  }

  void encodeSocket(core.Socket value, int offset, bool nullable) =>
      encodeHandle(value != null ? value.handle : null, offset, nullable);

  void encodeVmo(core.Vmo value, int offset, bool nullable) =>
      encodeHandle(value != null ? value.handle : null, offset, nullable);

  void encodeNullPointer(int offset, bool nullable) {
    if (!nullable) {
      throw new FidlCodecError(
          'Cannot encode a null pointer for a non-nullable type');
    }
    _buffer.buffer.setUint64(_base + offset, 0, Endianness.LITTLE_ENDIAN);
  }

  void encodeInvalidHandle(int offset, bool nullable) {
    if (!nullable) {
      throw new FidlCodecError(
          'Cannot encode a null pointer for a non-nullable type');
    }
    _buffer.buffer.setInt32(_base + offset, -1, Endianness.LITTLE_ENDIAN);
  }

  void encodePointerToNextUnclaimed(int offset) =>
      encodeUint64(_buffer.extent - (_base + offset), offset);

  void encodeStruct(Struct value, int offset, bool nullable) {
    if (value == null) {
      encodeNullPointer(offset, nullable);
      return;
    }
    encodePointerToNextUnclaimed(offset);
    value.encode(this);
  }

  void encodeUnion(Union value, int offset, bool nullable) {
    if (value == null) {
      if (!nullable) {
        throw new FidlCodecError('Cannot encode a non-nullable null union.');
      }
      encodeUint64(0, offset);
      encodeUint64(0, offset + 8);
      return;
    }
    value.encode(this, offset);
  }

  void encodeEnum(FidlEnum value, int offset) =>
      encodeUint32(value.fidlEnumValue, offset);

  void encodeNestedUnion(Union value, int offset, bool nullable) {
    encodePointerToNextUnclaimed(offset);
    var encoder = new Encoder._fromBuffer(_buffer);
    _buffer.claimMemory(_align(kUnionSize));
    encoder.encodeUnion(value, 0, nullable);
  }

  Encoder encodePointerArray(int length, int offset, int expectedLength) =>
      encoderForArray(kPointerSize, length, offset, expectedLength);

  Encoder encodeUnionArray(int length, int offset, int expectedLength) =>
      encoderForArray(kUnionSize, length, offset, expectedLength);

  Encoder encodeEnumArray(int length, int offset, int expectedLength) =>
      encoderForArray(kEnumSize, length, offset, expectedLength);

  Encoder encoderForArray(
      int elementSize, int length, int offset, int expectedLength) {
    if ((expectedLength != kUnspecifiedArrayLength) &&
        (expectedLength != length)) {
      throw new FidlCodecError(
          'Cannot encode a fixed array of incorrect length');
    }
    return encoderForArrayByTotalSize(length * elementSize, length, offset);
  }

  Encoder encoderForArrayByTotalSize(int size, int length, int offset) {
    encodePointerToNextUnclaimed(offset);
    return getArrayEncoderAtOffset(
        new ArrayDataHeader(ArrayDataHeader.kHeaderSize + size, length));
  }

  void encodeBoolArray(
      List<bool> value, int offset, int nullability, int expectedLength) {
    if (value == null) {
      encodeNullPointer(offset, isArrayNullable(nullability));
      return;
    }
    if ((expectedLength != kUnspecifiedArrayLength) &&
        (expectedLength != value.length)) {
      throw new FidlCodecError(
          'Cannot encode a fixed array of incorrect size.');
    }
    var bytes = new Uint8List((value.length + 7) >> kAlignmentShift);
    for (int i = 0; i < bytes.length; ++i) {
      for (int j = 0; j < kAlignment; ++j) {
        int boolIndex = kAlignment * i + j;
        if ((boolIndex < value.length) && value[boolIndex]) {
          bytes[i] |= (1 << j);
        }
      }
    }
    var encoder =
        encoderForArrayByTotalSize(bytes.length, value.length, offset);
    encoder.appendUint8Array(bytes);
  }

  void encodeArray(Function arrayAppend, int elementBytes, List value,
      int offset, int nullability, int expectedLength) {
    if (value == null) {
      encodeNullPointer(offset, isArrayNullable(nullability));
      return;
    }
    var encoder =
        encoderForArray(elementBytes, value.length, offset, expectedLength);
    arrayAppend(encoder, value);
  }

  void encodeInt8Array(
          List<int> value, int offset, int nullability, int expectedLength) =>
      encodeArray((e, v) => e.appendInt8Array(v), 1, value, offset, nullability,
          expectedLength);

  void encodeUint8Array(
          List<int> value, int offset, int nullability, int expectedLength) =>
      encodeArray((e, v) => e.appendUint8Array(v), 1, value, offset,
          nullability, expectedLength);

  void encodeInt16Array(
          List<int> value, int offset, int nullability, int expectedLength) =>
      encodeArray((e, v) => e.appendInt16Array(v), 2, value, offset,
          nullability, expectedLength);

  void encodeUint16Array(
          List<int> value, int offset, int nullability, int expectedLength) =>
      encodeArray((e, v) => e.appendUint16Array(v), 2, value, offset,
          nullability, expectedLength);

  void encodeInt32Array(
          List<int> value, int offset, int nullability, int expectedLength) =>
      encodeArray((e, v) => e.appendInt32Array(v), 4, value, offset,
          nullability, expectedLength);

  void encodeUint32Array(
          List<int> value, int offset, int nullability, int expectedLength) =>
      encodeArray((e, v) => e.appendUint32Array(v), 4, value, offset,
          nullability, expectedLength);

  void encodeInt64Array(
          List<int> value, int offset, int nullability, int expectedLength) =>
      encodeArray((e, v) => e.appendInt64Array(v), 8, value, offset,
          nullability, expectedLength);

  void encodeUint64Array(
          List<int> value, int offset, int nullability, int expectedLength) =>
      encodeArray((e, v) => e.appendUint64Array(v), 8, value, offset,
          nullability, expectedLength);

  void encodeFloatArray(List<double> value, int offset, int nullability,
          int expectedLength) =>
      encodeArray((e, v) => e.appendFloatArray(v), 4, value, offset,
          nullability, expectedLength);

  void encodeDoubleArray(List<double> value, int offset, int nullability,
          int expectedLength) =>
      encodeArray((e, v) => e.appendDoubleArray(v), 8, value, offset,
          nullability, expectedLength);

  void _handleArrayEncodeHelper(Function elementEncoder, List value, int offset,
      int elementSize, int nullability, int expectedLength) {
    if (value == null) {
      encodeNullPointer(offset, isArrayNullable(nullability));
      return;
    }
    var encoder =
        encoderForArray(elementSize, value.length, offset, expectedLength);
    for (int i = 0; i < value.length; ++i) {
      int elementOffset = ArrayDataHeader.kHeaderSize + elementSize * i;
      elementEncoder(
          encoder, value[i], elementOffset, isElementNullable(nullability));
    }
  }

  void encodeHandleArray(List<core.Handle> value, int offset, int nullability,
          int expectedLength) =>
      _handleArrayEncodeHelper((e, v, o, n) => e.encodeHandle(v, o, n), value,
          offset, kSerializedHandleSize, nullability, expectedLength);

  void encodeChannelArray(List<core.Channel> value, int offset, int nullability,
          int expectedLength) =>
      _handleArrayEncodeHelper((e, v, o, n) => e.encodeChannel(v, o, n), value,
          offset, kSerializedHandleSize, nullability, expectedLength);

  void encodeInterfaceRequestArray(List<InterfaceRequest> value, int offset,
          int nullability, int expectedLength) =>
      _handleArrayEncodeHelper(
          (e, v, o, n) => e.encodeInterfaceRequest(v, o, n),
          value,
          offset,
          kSerializedHandleSize,
          nullability,
          expectedLength);

  void encodeInterfaceHandleArray(List<InterfaceHandle> value, int offset,
          int nullability, int expectedLength) =>
      _handleArrayEncodeHelper((e, v, o, n) => e.encodeInterfaceHandle(v, o, n),
          value, offset, kSerializedInterfaceSize, nullability, expectedLength);

  void encodeSocketArray(List<core.Socket> value, int offset, int nullability,
          int expectedLength) =>
      _handleArrayEncodeHelper((e, v, o, n) => e.encodeSocket(v, o, n), value,
          offset, kSerializedHandleSize, nullability, expectedLength);

  static const Utf8Encoder _utf8Encoder = const Utf8Encoder();

  static Uint8List _utf8OfString(String string) =>
      (new Uint8List.fromList(_utf8Encoder.convert(string)));

  void encodeString(String value, int offset, bool nullable) {
    if (value == null) {
      encodeNullPointer(offset, nullable);
      return;
    }
    int nullability = nullable ? kArrayNullable : kNothingNullable;
    encodeUint8Array(
        _utf8OfString(value), offset, nullability, kUnspecifiedArrayLength);
  }

  void appendInt8Array(List<int> value) {
    int start = _base + ArrayDataHeader.kHeaderSize;
    int end = start + value.length;
    int idx = 0;
    for (int i = start; i < end; i++) {
      _buffer.buffer.setInt8(i, value[idx]);
      idx++;
    }
  }

  void appendUint8Array(List<int> value) {
    int start = _base + ArrayDataHeader.kHeaderSize;
    int end = start + value.length;
    int idx = 0;
    for (int i = start; i < end; i++) {
      _buffer.buffer.setUint8(i, value[idx]);
      idx++;
    }
  }

  void appendInt16Array(List<int> value) {
    int start = _base + ArrayDataHeader.kHeaderSize;
    int end = start + (value.length << 1);
    int idx = 0;
    for (int i = start; i < end; i += 2) {
      _buffer.buffer.setInt16(i, value[idx], Endianness.LITTLE_ENDIAN);
      idx++;
    }
  }

  void appendUint16Array(List<int> value) {
    int start = _base + ArrayDataHeader.kHeaderSize;
    int end = start + (value.length << 1);
    int idx = 0;
    for (int i = start; i < end; i += 2) {
      _buffer.buffer.setUint16(i, value[idx], Endianness.LITTLE_ENDIAN);
      idx++;
    }
  }

  void appendInt32Array(List<int> value) {
    int start = _base + ArrayDataHeader.kHeaderSize;
    int end = start + (value.length << 2);
    int idx = 0;
    for (int i = start; i < end; i += 4) {
      _buffer.buffer.setInt32(i, value[idx], Endianness.LITTLE_ENDIAN);
      idx++;
    }
  }

  void appendUint32Array(List<int> value) {
    int start = _base + ArrayDataHeader.kHeaderSize;
    int end = start + (value.length << 2);
    int idx = 0;
    for (int i = start; i < end; i += 4) {
      _buffer.buffer.setUint32(i, value[idx], Endianness.LITTLE_ENDIAN);
      idx++;
    }
  }

  void appendInt64Array(List<int> value) {
    int start = _base + ArrayDataHeader.kHeaderSize;
    int end = start + (value.length << 3);
    int idx = 0;
    for (int i = start; i < end; i += 8) {
      _buffer.buffer.setInt64(i, value[idx], Endianness.LITTLE_ENDIAN);
      idx++;
    }
  }

  void appendUint64Array(List<int> value) {
    int start = _base + ArrayDataHeader.kHeaderSize;
    int end = start + (value.length << 3);
    int idx = 0;
    for (int i = start; i < end; i += 8) {
      _buffer.buffer.setUint64(i, value[idx], Endianness.LITTLE_ENDIAN);
      idx++;
    }
  }

  void appendFloatArray(List<double> value) {
    int start = _base + ArrayDataHeader.kHeaderSize;
    int end = start + (value.length << 2);
    int idx = 0;
    for (int i = start; i < end; i += 4) {
      _buffer.buffer.setFloat32(i, value[idx], Endianness.LITTLE_ENDIAN);
      idx++;
    }
  }

  void appendDoubleArray(List<double> value) {
    int start = _base + ArrayDataHeader.kHeaderSize;
    int end = start + (value.length << 3);
    int idx = 0;
    for (int i = start; i < end; i += 8) {
      _buffer.buffer.setFloat64(i, value[idx], Endianness.LITTLE_ENDIAN);
      idx++;
    }
  }

  Encoder encoderForMap(int offset) {
    encodePointerToNextUnclaimed(offset);
    return getStructEncoderAtOffset(kMapStructHeader);
  }
}

class _Validator {
  final int _maxMemory;
  final int _numberOfHandles;
  int _minNextClaimedHandle = 0;
  int _minNextMemory = 0;
  final List<int> _skippedIndices = [];

  _Validator(this._maxMemory, this._numberOfHandles);

  void claimHandle(int handle) {
    if (handle < _minNextClaimedHandle) {
      throw new FidlCodecError('Cannot access handle out of order.');
    }
    if (handle >= _numberOfHandles) {
      throw new FidlCodecError('Cannot access non present handle.');
    }
    for (int i = _minNextClaimedHandle; i < handle; i++) {
      _skippedIndices.add(i);
    }
    _minNextClaimedHandle = handle + 1;
  }

  void claimMemory(int start, int end) {
    if ((start & kAlignmentMask) != 0) {
      throw new FidlCodecError('Incorrect starting alignment: $start.');
    }
    if (start < _minNextMemory) {
      throw new FidlCodecError('Cannot access memory out of order.');
    }
    if (end < start) {
      throw new FidlCodecError('Incorrect memory range.');
    }
    if (end > _maxMemory) {
      throw new FidlCodecError('Cannot access out of range memory.');
    }
    _minNextMemory = _align(end);
  }
}

class Decoder {
  _Validator _validator;
  Message _message;
  final int _base;

  Decoder(Message message, [this._base = 0, _Validator validator])
      : _message = message,
        _validator = (validator == null)
            ? new _Validator(message.dataLength, message.handlesLength)
            : validator;

  factory Decoder.atOffset(Decoder d, int offset, _Validator validator) =>
      new Decoder(d._message, offset, validator);

  Decoder getDecoderAtPosition(int offset) =>
      new Decoder(_message, offset, _validator);

  ByteData get _buffer => _message.buffer;
  List<core.Handle> get _handles => _message.handles;
  List<core.Handle> get excessHandles {
    if (_message.handlesLength == 0) return null;
    List<core.Handle> handles = new List();
    for (int i = _validator._minNextClaimedHandle;
        i < _message.handlesLength;
        i++) {
      handles.add(_message.handles[i]);
    }
    for (int i = 0; i < _validator._skippedIndices.length; i++) {
      handles.add(_message.handles[_validator._skippedIndices[i]]);
    }
    return handles;
  }

  int decodeInt8(int offset) => _buffer.getInt8(_base + offset);
  int decodeUint8(int offset) => _buffer.getUint8(_base + offset);
  int decodeInt16(int offset) =>
      _buffer.getInt16(_base + offset, Endianness.LITTLE_ENDIAN);
  int decodeUint16(int offset) =>
      _buffer.getUint16(_base + offset, Endianness.LITTLE_ENDIAN);
  int decodeInt32(int offset) =>
      _buffer.getInt32(_base + offset, Endianness.LITTLE_ENDIAN);
  int decodeUint32(int offset) =>
      _buffer.getUint32(_base + offset, Endianness.LITTLE_ENDIAN);
  int decodeInt64(int offset) =>
      _buffer.getInt64(_base + offset, Endianness.LITTLE_ENDIAN);
  int decodeUint64(int offset) =>
      _buffer.getUint64(_base + offset, Endianness.LITTLE_ENDIAN);
  double decodeFloat(int offset) =>
      _buffer.getFloat32(_base + offset, Endianness.LITTLE_ENDIAN);
  double decodeDouble(int offset) =>
      _buffer.getFloat64(_base + offset, Endianness.LITTLE_ENDIAN);

  bool decodeBool(int offset, int bit) =>
      (decodeUint8(offset) & (1 << bit)) != 0;

  core.Handle decodeHandle(int offset, bool nullable) {
    int index = decodeInt32(offset);
    if (index == -1) {
      if (!nullable) {
        throw new FidlCodecError(
            'Cannot decode an invalid handle from a non-nullable type.');
      }
      return new core.Handle.invalid();
    }
    _validator.claimHandle(index);
    return _handles[index];
  }

  core.Channel decodeChannel(int offset, bool nullable) =>
      new core.Channel(decodeHandle(offset, nullable));

  InterfaceHandle decodeInterfaceHandle(int offset, bool nullable) {
    final core.Channel channel = decodeChannel(offset, nullable);
    final int version = decodeUint32(offset + kSerializedHandleSize);
    if (!channel.handle.isValid) {
      return null;
    }
    return new InterfaceHandle(channel, version);
  }

  InterfaceRequest decodeInterfaceRequest(int offset, bool nullable) {
    final core.Channel channel = decodeChannel(offset, nullable);
    if (!channel.handle.isValid) return null;
    return new InterfaceRequest(channel);
  }

  core.Socket decodeSocket(int offset, bool nullable) =>
      new core.Socket(decodeHandle(offset, nullable));

  core.Vmo decodeVmo(int offset, bool nullable) =>
      new core.Vmo(decodeHandle(offset, nullable));

  Decoder decodePointer(int offset, bool nullable) {
    int basePosition = _base + offset;
    int pointerOffset = decodeUint64(offset);
    if (pointerOffset == 0) {
      if (!nullable) {
        throw new FidlCodecError(
            'Cannot decode a null pointer for a non-nullable type');
      }
      return null;
    }
    int newPosition = (basePosition + pointerOffset);
    return new Decoder.atOffset(this, newPosition, _validator);
  }

  StructDataHeader decodeStructDataHeader() {
    _validator.claimMemory(_base, _base + StructDataHeader.kHeaderSize);
    int size = decodeUint32(StructDataHeader.kSizeOffset);
    int version = decodeUint32(StructDataHeader.kVersionOffset);
    if (size < 0) {
      throw new FidlCodecError('Negative size.');
    }
    if (version < 0) {
      throw new FidlCodecError('Negative version number.');
    }
    _validator.claimMemory(_base + StructDataHeader.kHeaderSize, _base + size);
    return new StructDataHeader(size, version);
  }

  ArrayDataHeader decodeArrayDataHeader() {
    _validator.claimMemory(_base, _base + ArrayDataHeader.kHeaderSize);
    int size = decodeUint32(ArrayDataHeader.kSizeOffset);
    int numElements = decodeUint32(ArrayDataHeader.kNumElementsOffset);
    if (size < 0) {
      throw new FidlCodecError('Negative size.');
    }
    if (numElements < 0) {
      throw new FidlCodecError('Negative number of elements.');
    }
    _validator.claimMemory(_base + ArrayDataHeader.kHeaderSize, _base + size);
    return new ArrayDataHeader(size, numElements);
  }

  // Decode arrays.
  ArrayDataHeader decodeDataHeaderForBoolArray(int expectedLength) {
    var header = decodeArrayDataHeader();
    var arrayByteCount = ArrayDataHeader.kHeaderSize +
        ((header.numElements + 7) >> kAlignmentShift);
    if (header.size < arrayByteCount) {
      throw new FidlCodecError('Array header is incorrect');
    }
    if ((expectedLength != kUnspecifiedArrayLength) &&
        (header.numElements != expectedLength)) {
      throw new FidlCodecError(
          'Incorrect array length. Expected $expectedLength, but got '
          '${header.numElements}.');
    }
    return header;
  }

  List<bool> decodeBoolArray(int offset, int nullability, int expectedLength) {
    Decoder d = decodePointer(offset, isArrayNullable(nullability));
    if (d == null) {
      return null;
    }
    var header = d.decodeDataHeaderForBoolArray(expectedLength);
    var bytes = new Uint8List.view(
        d._buffer.buffer,
        d._buffer.offsetInBytes + d._base + ArrayDataHeader.kHeaderSize,
        ((header.numElements + 7) >> kAlignmentShift));
    var result = new List<bool>(header.numElements);
    for (int i = 0; i < bytes.lengthInBytes; ++i) {
      for (int j = 0; j < kAlignment; ++j) {
        int boolIndex = i * kAlignment + j;
        if (boolIndex < result.length) {
          result[boolIndex] = (bytes[i] & (1 << j)) != 0;
        }
      }
    }
    return result;
  }

  ArrayDataHeader decodeDataHeaderForArray(
      int elementSize, int expectedLength) {
    var header = decodeArrayDataHeader();
    var arrayByteCount =
        ArrayDataHeader.kHeaderSize + header.numElements * elementSize;
    if (header.size < arrayByteCount) {
      throw new FidlCodecError(
          'Array header is incorrect: $header, elementSize = $elementSize');
    }
    if ((expectedLength != kUnspecifiedArrayLength) &&
        (header.numElements != expectedLength)) {
      throw new FidlCodecError(
          'Incorrect array length. Expected $expectedLength, but got '
          '${header.numElements}');
    }
    return header;
  }

  ArrayDataHeader decodeDataHeaderForPointerArray(int expectedLength) =>
      decodeDataHeaderForArray(kPointerSize, expectedLength);

  ArrayDataHeader decodeDataHeaderForUnionArray(int expectedLength) =>
      decodeDataHeaderForArray(kUnionSize, expectedLength);

  ArrayDataHeader decodeDataHeaderForEnumArray(int expectedLength) =>
      decodeDataHeaderForArray(kEnumSize, expectedLength);

  Int8List decodeInt8Array(int offset, int nullability, int expectedLength) {
    Decoder d = decodePointer(offset, isArrayNullable(nullability));
    if (d == null) {
      return null;
    }
    var header = d.decodeDataHeaderForArray(1, expectedLength);
    int startByte = d._base + ArrayDataHeader.kHeaderSize;
    int endByte = startByte + header.numElements;
    Int8List result = new Int8List(header.numElements);
    int resultIdx = 0;
    for (int i = startByte; i < endByte; i++) {
      result[resultIdx] = d._buffer.getInt8(i);
      resultIdx++;
    }
    return result;
  }

  Uint8List decodeUint8Array(int offset, int nullability, int expectedLength) {
    Decoder d = decodePointer(offset, isArrayNullable(nullability));
    if (d == null) {
      return null;
    }
    var header = d.decodeDataHeaderForArray(1, expectedLength);
    int startByte = d._base + ArrayDataHeader.kHeaderSize;
    int endByte = startByte + header.numElements;
    Uint8List result = new Uint8List(header.numElements);
    int resultIdx = 0;
    for (int i = startByte; i < endByte; i++) {
      result[resultIdx] = d._buffer.getUint8(i);
      resultIdx++;
    }
    return result;
  }

  Int16List decodeInt16Array(int offset, int nullability, int expectedLength) {
    Decoder d = decodePointer(offset, isArrayNullable(nullability));
    if (d == null) {
      return null;
    }
    var header = d.decodeDataHeaderForArray(2, expectedLength);
    int startByte = d._base + ArrayDataHeader.kHeaderSize;
    int endByte = startByte + (header.numElements << 1);
    Int16List result = new Int16List(header.numElements);
    int resultIdx = 0;
    for (int i = startByte; i < endByte; i += 2) {
      result[resultIdx] = d._buffer.getInt16(i, Endianness.LITTLE_ENDIAN);
      resultIdx++;
    }
    return result;
  }

  Uint16List decodeUint16Array(
      int offset, int nullability, int expectedLength) {
    Decoder d = decodePointer(offset, isArrayNullable(nullability));
    if (d == null) {
      return null;
    }
    var header = d.decodeDataHeaderForArray(2, expectedLength);
    int startByte = d._base + ArrayDataHeader.kHeaderSize;
    int endByte = startByte + (header.numElements << 1);
    Uint16List result = new Uint16List(header.numElements);
    int resultIdx = 0;
    for (int i = startByte; i < endByte; i += 2) {
      result[resultIdx] = d._buffer.getUint16(i, Endianness.LITTLE_ENDIAN);
      resultIdx++;
    }
    return result;
  }

  Int32List decodeInt32Array(int offset, int nullability, int expectedLength) {
    Decoder d = decodePointer(offset, isArrayNullable(nullability));
    if (d == null) {
      return null;
    }
    var header = d.decodeDataHeaderForArray(4, expectedLength);
    int startByte = d._base + ArrayDataHeader.kHeaderSize;
    int endByte = startByte + (header.numElements << 2);
    Int32List result = new Int32List(header.numElements);
    int resultIdx = 0;
    for (int i = startByte; i < endByte; i += 4) {
      result[resultIdx] = d._buffer.getInt32(i, Endianness.LITTLE_ENDIAN);
      resultIdx++;
    }
    return result;
  }

  Uint32List decodeUint32Array(
      int offset, int nullability, int expectedLength) {
    Decoder d = decodePointer(offset, isArrayNullable(nullability));
    if (d == null) {
      return null;
    }
    var header = d.decodeDataHeaderForArray(4, expectedLength);
    int startByte = d._base + ArrayDataHeader.kHeaderSize;
    int endByte = startByte + (header.numElements << 2);
    Uint32List result = new Uint32List(header.numElements);
    int resultIdx = 0;
    for (int i = startByte; i < endByte; i += 4) {
      result[resultIdx] = d._buffer.getUint32(i, Endianness.LITTLE_ENDIAN);
      resultIdx++;
    }
    return result;
  }

  Int64List decodeInt64Array(int offset, int nullability, int expectedLength) {
    Decoder d = decodePointer(offset, isArrayNullable(nullability));
    if (d == null) {
      return null;
    }
    var header = d.decodeDataHeaderForArray(8, expectedLength);
    int startByte = d._base + ArrayDataHeader.kHeaderSize;
    int endByte = startByte + (header.numElements << 3);
    Int64List result = new Int64List(header.numElements);
    int resultIdx = 0;
    for (int i = startByte; i < endByte; i += 8) {
      result[resultIdx] = d._buffer.getInt64(i, Endianness.LITTLE_ENDIAN);
      resultIdx++;
    }
    return result;
  }

  Uint64List decodeUint64Array(
      int offset, int nullability, int expectedLength) {
    Decoder d = decodePointer(offset, isArrayNullable(nullability));
    if (d == null) {
      return null;
    }
    var header = d.decodeDataHeaderForArray(8, expectedLength);
    int startByte = d._base + ArrayDataHeader.kHeaderSize;
    int endByte = startByte + (header.numElements << 3);
    Uint64List result = new Uint64List(header.numElements);
    int resultIdx = 0;
    for (int i = startByte; i < endByte; i += 8) {
      result[resultIdx] = d._buffer.getUint64(i, Endianness.LITTLE_ENDIAN);
      resultIdx++;
    }
    return result;
  }

  Float32List decodeFloatArray(
      int offset, int nullability, int expectedLength) {
    Decoder d = decodePointer(offset, isArrayNullable(nullability));
    if (d == null) {
      return null;
    }
    var header = d.decodeDataHeaderForArray(4, expectedLength);
    int startByte = d._base + ArrayDataHeader.kHeaderSize;
    int endByte = startByte + (header.numElements << 2);
    Float32List result = new Float32List(header.numElements);
    int resultIdx = 0;
    for (int i = startByte; i < endByte; i += 4) {
      result[resultIdx] = d._buffer.getFloat32(i, Endianness.LITTLE_ENDIAN);
      resultIdx++;
    }
    return result;
  }

  Float64List decodeDoubleArray(
      int offset, int nullability, int expectedLength) {
    Decoder d = decodePointer(offset, isArrayNullable(nullability));
    if (d == null) {
      return null;
    }
    var header = d.decodeDataHeaderForArray(8, expectedLength);
    int startByte = d._base + ArrayDataHeader.kHeaderSize;
    int endByte = startByte + (header.numElements << 3);
    Float64List result = new Float64List(header.numElements);
    int resultIdx = 0;
    for (int i = startByte; i < endByte; i += 8) {
      result[resultIdx] = d._buffer.getFloat64(i, Endianness.LITTLE_ENDIAN);
      resultIdx++;
    }
    return result;
  }

  List _handleArrayDecodeHelper(Function elementDecoder, int offset,
      int elementSize, int nullability, int expectedLength) {
    Decoder d = decodePointer(offset, isArrayNullable(nullability));
    if (d == null) {
      return null;
    }
    var header = d.decodeDataHeaderForArray(elementSize, expectedLength);
    var result = new List(header.numElements);
    for (int i = 0; i < result.length; ++i) {
      result[i] = elementDecoder(
          d,
          ArrayDataHeader.kHeaderSize + elementSize * i,
          isElementNullable(nullability));
    }
    return result;
  }

  List<core.Handle> decodeHandleArray(
          int offset, int nullability, int expectedLength) =>
      _handleArrayDecodeHelper((d, o, n) => d.decodeHandle(o, n), offset,
          kSerializedHandleSize, nullability, expectedLength);

  List<core.Channel> decodeChannelArray(
          int offset, int nullability, int expectedLength) =>
      _handleArrayDecodeHelper((d, o, n) => d.decodeChannel(o, n), offset,
          kSerializedHandleSize, nullability, expectedLength);

  List<InterfaceRequest> decodeInterfaceRequestArray(
      int offset, int nullability, int expectedLength) {
    return _handleArrayDecodeHelper((d, o, n) => d.decodeInterfaceRequest(o, n),
        offset, kSerializedHandleSize, nullability, expectedLength);
  }

  List<InterfaceHandle> decodeInterfaceHandleArray(
      int offset, int nullability, int expectedLength) {
    return _handleArrayDecodeHelper((d, o, n) => d.decodeInterfaceHandle(o, n),
        offset, kSerializedInterfaceSize, nullability, expectedLength);
  }

  List<core.Socket> decodeSocketArray(
          int offset, int nullability, int expectedLength) =>
      _handleArrayDecodeHelper((d, o, n) => d.decodeSocket(o, n), offset,
          kSerializedHandleSize, nullability, expectedLength);

  static const _utf8Decoder = const Utf8Decoder();

  String decodeString(int offset, bool nullable) {
    int nullability = nullable ? kArrayNullable : 0;
    var bytes = decodeUint8Array(offset, nullability, kUnspecifiedArrayLength);
    if (bytes == null) {
      return null;
    }
    return _utf8Decoder.convert(bytes);
  }

  StructDataHeader decodeDataHeaderForMap() {
    var header = decodeStructDataHeader();
    if (header.size != kMapStructHeader.size) {
      throw new FidlCodecError(
          'Incorrect header for map. The size is incorrect.');
    }
    if (header.version != kMapStructHeader.version) {
      throw new FidlCodecError(
          'Incorrect header for map. The version is incorrect.');
    }
    return header;
  }
}

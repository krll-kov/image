import 'dart:typed_data';

import '../../util/_internal.dart';

@internal

/// Bit writer that packs bits LSB-first into bytes.
class VP8LBitWriter {
  final _bytes = <int>[];
  int _currentByte = 0;
  int _usedBits = 0;

  @pragma('vm:unsafe:no-bounds-checks')
  void writeBits(int value, int numBits) {
    while (numBits > 0) {
      final available = 8 - _usedBits;
      final bitsToWrite = numBits < available ? numBits : available;
      final mask = (1 << bitsToWrite) - 1;
      _currentByte |= (value & mask) << _usedBits;
      value >>= bitsToWrite;
      numBits -= bitsToWrite;
      _usedBits += bitsToWrite;
      if (_usedBits == 8) {
        _bytes.add(_currentByte);
        _currentByte = 0;
        _usedBits = 0;
      }
    }
  }

  void flush() {
    if (_usedBits > 0) {
      _bytes.add(_currentByte);
      _currentByte = 0;
      _usedBits = 0;
    }
  }

  Uint8List getBytes() => Uint8List.fromList(_bytes);
}

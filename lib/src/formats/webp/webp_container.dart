/// Building the RIFF container a WebP file is wrapped in.
///
/// A single still frame with no metadata needs nothing but a RIFF header and
/// the bitstream. Anything more — animation, an ICC profile, EXIF or XMP — has
/// to go in the extended format, which announces what is present in a VP8X
/// chunk and then carries each part as its own chunk.
library;

import 'dart:typed_data';

import '../../util/_internal.dart';
import '../../util/output_buffer.dart';

/// A chunk of a WebP file: a four character tag and its payload.
@internal
class WebPChunk {
  WebPChunk(this.tag, this.data);

  final String tag;
  final Uint8List data;

  /// Chunks are padded to an even length, and the pad byte is not counted in
  /// the size field.
  int get diskSize => 8 + data.length + (data.length.isOdd ? 1 : 0);

  void writeTo(OutputBuffer out) {
    out
      ..writeBytes(webPTag(tag))
      ..writeUint32(data.length)
      ..writeBytes(data);
    if (data.length.isOdd) {
      out.writeByte(0);
    }
  }
}

/// The four bytes of a chunk tag.
@internal
Uint8List webPTag(String s) {
  final bytes = Uint8List(s.length);
  for (var i = 0; i < s.length; i++) {
    bytes[i] = s.codeUnitAt(i);
  }
  return bytes;
}

/// The flags byte of a VP8X chunk.
@internal
int vp8xFlags(
        {required bool hasIcc,
        required bool hasAlpha,
        required bool hasExif,
        required bool hasXmp,
        required bool hasAnimation}) =>
    (hasIcc ? 1 << 5 : 0) |
    (hasAlpha ? 1 << 4 : 0) |
    (hasExif ? 1 << 3 : 0) |
    (hasXmp ? 1 << 2 : 0) |
    (hasAnimation ? 1 << 1 : 0);

/// The VP8X chunk payload: the flags and the canvas size.
@internal
Uint8List vp8xChunkData(int flags, int width, int height) {
  final out = OutputBuffer()
    ..writeByte(flags)
    ..writeByte(0) // reserved, 24 bits
    ..writeByte(0)
    ..writeByte(0);
  _writeUint24(out, width - 1);
  _writeUint24(out, height - 1);
  return out.getBytes();
}

/// The ANIM chunk payload: the canvas background color and the loop count.
@internal
Uint8List animChunkData(int r, int g, int b, int a, int loopCount) {
  // The decoder reads the color back as blue, green, red, alpha from the top
  // byte down, so pack it that way.
  final out = OutputBuffer()
    ..writeUint32((b << 24) | (g << 16) | (r << 8) | a)
    ..writeUint16(loopCount);
  return out.getBytes();
}

/// One ANMF chunk: the frame's placement and timing, then its bitstream.
@internal
Uint8List anmfChunkData(
    {required int x,
    required int y,
    required int width,
    required int height,
    required int duration,
    required bool clearToBackground,
    required Uint8List bitstream}) {
  final out = OutputBuffer();
  // The offsets are stored halved, so they are always even.
  _writeUint24(out, x >> 1);
  _writeUint24(out, y >> 1);
  _writeUint24(out, width - 1);
  _writeUint24(out, height - 1);
  _writeUint24(out, duration);
  out
    ..writeByte(clearToBackground ? 1 : 0)
    ..writeBytes(webPTag('VP8L'))
    ..writeUint32(bitstream.length)
    ..writeBytes(bitstream);
  if (bitstream.length.isOdd) {
    out.writeByte(0);
  }
  return out.getBytes();
}

/// Wraps [chunks] in the RIFF/WEBP header.
@internal
Uint8List buildRiff(List<WebPChunk> chunks) {
  var payload = 4; // the 'WEBP' tag
  for (final c in chunks) {
    payload += c.diskSize;
  }

  final out = OutputBuffer()
    ..writeBytes(webPTag('RIFF'))
    ..writeUint32(payload)
    ..writeBytes(webPTag('WEBP'));
  for (final c in chunks) {
    c.writeTo(out);
  }
  return out.getBytes();
}

void _writeUint24(OutputBuffer out, int v) {
  out
    ..writeByte(v & 0xff)
    ..writeByte((v >> 8) & 0xff)
    ..writeByte((v >> 16) & 0xff);
}

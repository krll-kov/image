import 'dart:typed_data';

import '../image/image.dart';
import '../util/output_buffer.dart';
import 'encoder.dart';
import 'webp/vp8l_encoder.dart';
import 'webp/webp_container.dart';

/// Encode an image to the WebP format (lossless).
///
/// Uses the VP8L lossless bitstream format wrapped in a RIFF/WebP container.
/// Animation, an ICC profile and EXIF are carried in the extended format when
/// the image has them. XMP is not: the decoder reports it on WebPInfo but never
/// puts it on the Image, so there is nothing here to write back.
class WebPEncoder extends Encoder {
  WebPEncoder({this.exact = false});

  /// Whether to preserve the colour under fully transparent pixels.
  ///
  /// Those pixels show nothing, so by default the colour beneath them is
  /// flattened into long runs, which compresses considerably better on images
  /// with large transparent areas. Set this when the hidden colour matters,
  /// for instance when the file is a step in a pipeline that will composite
  /// it later. cwebp spells the same option `-exact`.
  final bool exact;

  @override
  bool get supportsAnimation => true;

  @override
  Uint8List encode(Image image, {bool singleFrame = false}) {
    final animate = !singleFrame && image.hasAnimation;
    final exif = _exifBytes(image);
    // WebP stores the ICC profile raw; deflating it, the way PNG's iCCP chunk
    // does, would make it unreadable.
    final icc = image.iccProfile?.decompressed();

    // Nothing but pixels: the simple container is smaller, and is what every
    // reader handles.
    if (!animate && exif == null && icc == null) {
      return buildRiff([
        WebPChunk('VP8L', VP8LEncoder(exact: exact).encodeVP8L(image)),
      ]);
    }

    final chunks = <WebPChunk>[
      WebPChunk(
          'VP8X',
          vp8xChunkData(
              vp8xFlags(
                hasIcc: icc != null,
                hasAlpha: image.numChannels >= 4,
                hasExif: exif != null,
                hasXmp: false,
                hasAnimation: animate,
              ),
              image.width,
              image.height)),
    ];

    if (icc != null) {
      chunks.add(WebPChunk('ICCP', icc));
    }

    if (animate) {
      final bg = image.backgroundColor;
      chunks.add(WebPChunk(
          'ANIM',
          animChunkData(bg?.r.toInt() ?? 0, bg?.g.toInt() ?? 0,
              bg?.b.toInt() ?? 0, bg?.a.toInt() ?? 0, image.loopCount)));
      for (final frame in image.frames) {
        chunks.add(WebPChunk(
            'ANMF',
            anmfChunkData(
              x: 0,
              y: 0,
              width: frame.width,
              height: frame.height,
              duration: frame.frameDuration,
              // Frames are stored whole rather than as deltas against the
              // previous one, so each starts from a cleared canvas.
              clearToBackground: true,
              bitstream: VP8LEncoder(exact: exact).encodeVP8L(frame),
            )));
      }
    } else {
      chunks
          .add(WebPChunk('VP8L', VP8LEncoder(exact: exact).encodeVP8L(image)));
    }

    if (exif != null) {
      chunks.add(WebPChunk('EXIF', exif));
    }
    return buildRiff(chunks);
  }

  static Uint8List? _exifBytes(Image image) {
    if (image.exif.isEmpty) {
      return null;
    }
    final out = OutputBuffer();
    image.exif.write(out);
    return out.getBytes();
  }
}

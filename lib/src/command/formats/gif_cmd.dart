import 'dart:typed_data';

import '../../filter/dither_image.dart';
import '../../formats/formats.dart';
import '../command.dart';

/// Decode a GIF Image from byte [data].
class DecodeGifCmd extends Command {
  Uint8List data;

  DecodeGifCmd(Command? input, this.data) : super(input);

  @override
  Future<void> executeCommand() async {
    await input?.execute();
    outputImage = decodeGif(data);
  }
}

/// Decode a GIF Image from a file at the given [path].
class DecodeGifFileCmd extends Command {
  String path;

  DecodeGifFileCmd(Command? input, this.path) : super(input);

  @override
  Future<void> executeCommand() async {
    await input?.execute();
    outputImage = await decodeGifFile(path);
  }
}

/// Encode an Image to the GIF format.
class EncodeGifCmd extends Command {
  int samplingFactor;
  DitherKernel dither;

  /// Deprecated: use [ditherScanOrder] instead.
  @Deprecated('Use ditherScanOrder: DitherScanOrder.serpentine instead. '
      'This will be removed in a future release.')
  bool ditherSerpentine;

  DitherScanOrder? ditherScanOrder;

  EncodeGifCmd(
    Command? input, {
    this.samplingFactor = 10,
    this.dither = DitherKernel.floydSteinberg,
    @Deprecated('Use ditherScanOrder: DitherScanOrder.serpentine instead. '
        'This will be removed in a future release.')
    this.ditherSerpentine = false,
    this.ditherScanOrder,
  }) : super(input);

  DitherScanOrder get scanOrder =>
      ditherScanOrder ??
      // ignore: deprecated_member_use_from_same_package
      (ditherSerpentine ? DitherScanOrder.serpentine : DitherScanOrder.raster);

  @override
  Future<void> executeCommand() async {
    await input?.execute();
    outputImage = input?.outputImage;
    if (outputImage != null) {
      outputBytes = encodeGif(
        outputImage!,
        samplingFactor: samplingFactor,
        dither: dither,
        ditherScanOrder: scanOrder,
      );
    }
  }
}

/// Encode an Image to the GIF format and write it to a file at the given
/// [path].
class EncodeGifFileCmd extends EncodeGifCmd {
  String path;

  EncodeGifFileCmd(
    Command? input,
    this.path, {
    int samplingFactor = 10,
    DitherKernel dither = DitherKernel.floydSteinberg,
    @Deprecated('Use ditherScanOrder: DitherScanOrder.serpentine instead. '
        'This will be removed in a future release.')
    bool ditherSerpentine = false,
    DitherScanOrder? ditherScanOrder,
  }) : super(
          input,
          samplingFactor: samplingFactor,
          dither: dither,
          ditherScanOrder: ditherScanOrder ??
              // ignore: deprecated_member_use_from_same_package
              (ditherSerpentine
                  ? DitherScanOrder.serpentine
                  : DitherScanOrder.raster),
        );

  @override
  Future<void> executeCommand() async {
    await input?.execute();
    outputImage = input?.outputImage;
    if (outputImage != null) {
      await encodeGifFile(
        path,
        outputImage!,
        samplingFactor: samplingFactor,
        dither: dither,
        ditherScanOrder: scanOrder,
      );
    }
  }
}

import '../../filter/dither_image.dart' as g;
import '../../util/quantizer.dart';
import '../command.dart';

class DitherImageCmd extends Command {
  final Quantizer? quantizer;
  final g.DitherKernel kernel;

  /// Use [scanOrder] instead.
  final bool serpentine;

  final g.DitherScanOrder? scanOrder;

  DitherImageCmd(
    Command? input, {
    this.quantizer,
    this.kernel = g.DitherKernel.floydSteinberg,
    this.serpentine = false,
    this.scanOrder,
  }) : super(input);

  @override
  Future<void> executeCommand() async {
    await input?.execute();
    final img = input?.outputImage;
    final order = scanOrder ??
        (serpentine ? g.DitherScanOrder.serpentine : g.DitherScanOrder.raster);
    outputImage = img != null
        ? g.ditherImage(img,
            quantizer: quantizer, kernel: kernel, scanOrder: order)
        : null;
  }
}

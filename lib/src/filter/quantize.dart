import '../image/image.dart';
import '../util/binary_quantizer.dart';
import '../util/neural_quantizer.dart';
import '../util/octree_quantizer.dart';
import '../util/quantizer.dart';
import 'dither_image.dart';

enum QuantizeMethod { neuralNet, octree, binary }

/// Quantize the number of colors in image to 256.
///
/// `ditherSerpentine` is deprecated in favor of [ditherScanOrder] and is
/// ignored when [ditherScanOrder] is given explicitly.
Image quantize(
  Image src, {
  int numberOfColors = 256,
  QuantizeMethod method = QuantizeMethod.neuralNet,
  DitherKernel dither = DitherKernel.none,
  @Deprecated('Use ditherScanOrder: DitherScanOrder.serpentine instead. '
      'This parameter will be removed in a future release.')
  bool ditherSerpentine = false,
  DitherScanOrder? ditherScanOrder,
}) {
  Quantizer quantizer;

  if (method == QuantizeMethod.octree || numberOfColors < 4) {
    quantizer = OctreeQuantizer(src, numberOfColors: numberOfColors);
  } else if (method == QuantizeMethod.neuralNet) {
    quantizer = NeuralQuantizer(src, numberOfColors: numberOfColors);
  } else {
    quantizer = BinaryQuantizer();
  }

  final order = ditherScanOrder ??
      // ignore: deprecated_member_use_from_same_package
      (ditherSerpentine ? DitherScanOrder.serpentine : DitherScanOrder.raster);

  return ditherImage(
    src,
    quantizer: quantizer,
    kernel: dither,
    scanOrder: order,
  );
}

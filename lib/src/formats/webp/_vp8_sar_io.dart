import '../../util/_internal.dart';

/// Arithmetic right shift of a signed 32-bit value.
///
/// On the VM an `int` is a 64-bit two's complement integer and `>>` already
/// has this meaning, so this is the operator itself. The web needs a
/// correction; see `_vp8_sar_html.dart`.
@internal
@pragma('vm:prefer-inline')
int sar(int value, int shift) => value >> shift;

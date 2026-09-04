/// A right shift that means the same thing on the VM and on the web.
///
/// Only needed where the value being shifted can be negative. Where it cannot,
/// the plain operator is correct everywhere and is what the code should use.
library;

export '_vp8_sar_html.dart' if (dart.library.io) '_vp8_sar_io.dart';

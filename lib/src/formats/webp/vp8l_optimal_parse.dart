/// Choosing how to cover the image with literals and matches so that the whole
/// stream costs as little as possible.
///
/// Lazy matching decides one token at a time, looking a single position ahead.
/// That is cheap and wrong: whether a match is worth taking depends on what the
/// rest of the image does with the pixels it consumes, which a one-step
/// lookahead cannot see. Here every position is instead given the cheapest way
/// of reaching it from any earlier one, which is a shortest path, and the
/// answer falls out by walking the predecessors back. libwebp calls the same
/// idea `BackwardReferencesHashChainDistanceOnly` followed by `TraceBackwards`.
library;

import 'dart:typed_data';

import '../../util/_internal.dart';
import 'vp8l_backward_refs.dart';

/// Shortest match worth coding; below this a literal is cheaper.
const _minMatchLen = 3;

/// How many lengths of a match are weighed individually before only its full
/// extent is considered.
///
/// Cost grows with length in steps, not smoothly, so nearly all of the choice
/// lives among the shortest few; past this the only length that tends to win
/// is the longest available. Weighing every length instead, the way libwebp's
/// interval-based cost manager does, would make the parse cost the length of
/// the longest match at every pixel: measured at 48 it buys 0.01% over 16.
const _lengthsWeighed = 16;

/// The cheapest cover of the image, as the number of pixels the token starting
/// at each position spans.
///
/// Positions inside a token hold 0 and are never read.
@internal
@pragma('vm:unsafe:no-bounds-checks')
Int32List optimalCover(
    VP8LMatches matches,
    VP8LCostModel costs,
    Uint8List r,
    Uint8List g,
    Uint8List b,
    Uint8List a,
    int numPixels,
    int width,
    Int32List coverDistance) {
  // cost[i] is the cheapest way to code the first i pixels; from[i] is how many
  // pixels the last token of that way covers.
  final cost = Float64List(numPixels + 1)
    ..fillRange(1, numPixels + 1, double.infinity);
  final from = Int32List(numPixels + 1);
  final fromDistance = Int32List(numPixels + 1);
  final lengthBits = costs.lengthBits;
  final matchLen = matches.length;
  final matchDist = matches.distance;
  final cheapLen = matches.cheapLength;
  final cheapDists = matches.cheapDistances;
  // Each near-neighbour distance costs the same wherever it is used.
  final cheapDistBits = [
    for (final d in cheapDists) costs.distanceBits(d, width),
  ];
  final candidates = 1 + cheapDists.length;

  for (var i = 0; i < numPixels; i++) {
    final here = cost[i];

    // Coding this pixel on its own is always possible, so every position is
    // reachable and the parse can never fail.
    final asLiteral = here + costs.literalCost(r, g, b, a, i);
    if (asLiteral < cost[i + 1]) {
      cost[i + 1] = asLiteral;
      from[i + 1] = 1;
    }

    // Every way of reaching further is weighed: whatever the search settled
    // on, and each near-neighbour offset. The search already tries those and
    // keeps one only when it is longest, but a shorter match at a
    // near-neighbour distance can still win here, since those are the cheapest
    // distances the format codes.
    for (var which = 0; which < candidates; which++) {
      final int maxLen;
      final int dist;
      final double distBits;
      if (which == 0) {
        maxLen = matchLen[i];
        dist = matchDist[i];
        distBits = here + costs.distanceBits(dist, width);
      } else {
        maxLen = cheapLen[which - 1][i];
        dist = cheapDists[which - 1];
        distBits = here + cheapDistBits[which - 1];
      }
      if (maxLen < _minMatchLen) {
        continue;
      }

      final weighed = maxLen < _lengthsWeighed ? maxLen : _lengthsWeighed;
      for (var len = _minMatchLen; len <= weighed; len++) {
        final c = distBits + lengthBits[len];
        if (c < cost[i + len]) {
          cost[i + len] = c;
          from[i + len] = len;
          fromDistance[i + len] = dist;
        }
      }
      if (maxLen > weighed) {
        final c = distBits + lengthBits[maxLen];
        if (c < cost[i + maxLen]) {
          cost[i + maxLen] = c;
          from[i + maxLen] = maxLen;
          fromDistance[i + maxLen] = dist;
        }
      }
    }
  }

  // Walk the predecessors back, then turn the chain around so that each token
  // is recorded at the position it starts from.
  final cover = Int32List(numPixels);
  var at = numPixels;
  while (at > 0) {
    final len = from[at];
    cover[at - len] = len;
    coverDistance[at - len] = fromDistance[at];
    at -= len;
  }
  return cover;
}

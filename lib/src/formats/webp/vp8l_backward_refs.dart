/// Turning pixels into the token stream a VP8L image codes: literals and LZ77
/// back-references.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../../util/_internal.dart';
import 'vp8l_huffman_encoder.dart' as huffman;

/// The token stream for one image: literals and back-references in the order
/// they are coded, plus where in the image each one starts.
@internal
class VP8LBackwardRefs {
  VP8LBackwardRefs(this.isLiteral, this.literalIndex, this.length,
      this.distance, this.position);

  /// One entry per token: whether it is a literal or a back-reference.
  final List<bool> isLiteral;

  /// Pixel index of each literal, in literal order.
  final List<int> literalIndex;

  /// Match length of each back-reference, in back-reference order.
  final List<int> length;

  /// Match distance of each back-reference, in back-reference order.
  final List<int> distance;

  /// Pixel index each token starts at, in token order. Meta Huffman uses this
  /// to decide which group of codes a token belongs to.
  final Int32List position;
}

/// How far back the chain of candidate positions is followed.
///
/// libwebp's `GetMaxItersForQuality` tops out at 86 even at quality 100, and it
/// is the value tuned over a far wider corpus than anything measured here.
const _maxChain = 86;

/// Longest match the tokenizer will emit.
const _maxMatchLen = 4096;

/// The spec caps the distance at 1048576, and the first 120 values are taken by
/// the near-neighbour plane codes, leaving this as the real maximum.
const _maxDistance = 1048456;

/// The longest match reachable from each position, as parallel arrays.
///
/// A parse that considers every way of covering the image needs the answer at
/// every pixel, so the whole table is built up front.
@internal
class VP8LMatches {
  VP8LMatches(
      this.length, this.distance, this.cheapLength, this.cheapDistances);

  /// Match length at each pixel position, 0 where nothing matches.
  final Int32List length;

  /// Match distance at each pixel position, meaningless where length is 0.
  final Int32List distance;

  /// How far each of [cheapDistances] repeats from every position.
  ///
  /// These are the offsets that land on the near-neighbour plane codes, which
  /// are the cheapest distances the format has. They are worth keeping even
  /// when the chain finds something longer, since a shorter match at a
  /// near-neighbour distance can still cost less. The chain on its own would
  /// have to walk back a whole row of candidates to reach the one directly
  /// above, which is past the search limit.
  /// Lengths never exceed [_maxMatchLen], so sixteen bits are enough, and
  /// there is one of these per offset per pixel.
  final List<Uint16List> cheapLength;

  /// The distance each entry of [cheapLength] corresponds to.
  final List<int> cheapDistances;
}

/// Finds the best match at every position.
///
/// Positions are visited from the end backwards, because a match found at one
/// position usually answers for its neighbours too: if the same distance still
/// matches one pixel to the left, that pixel's best match is this one grown by
/// one, and no search is needed for it. On flat or repetitive images a single
/// search then covers a whole run, which is most of what makes such images
/// cheap to encode. libwebp does the same in `VP8LHashChainFill`.
@internal
VP8LMatches computeMatches(Uint8List r, Uint8List g, Uint8List b, Uint8List a,
    int numPixels, int width) {
  final lz = _Lz77(r, g, b, a, numPixels)..fillChain();
  final px = lz._px;
  final prev = lz._prev;
  final length = Int32List(numPixels);
  final distance = Int32List(numPixels);

  // The offsets reaching the nearest plane codes: the pixel before, the one
  // before that, and the three directly above and to either side.
  //
  // libwebp's kLZ77Box strategy tries every offset whose plane code is a near
  // neighbour, some ninety of them. Carrying the next ring out as well was
  // measured at 0.04 points of the corpus for 19% more encode time, which is
  // the wrong way round while size is inside budget and speed is not.
  final cheapDistances = <int>[1, 2, width - 1, width, width + 1]
      .where((d) => d >= 1 && d < numPixels)
      .toSet()
      .toList()
    ..sort();
  final cheapLength = [
    for (final _ in cheapDistances) Uint16List(numPixels),
  ];

  // Taken from the right: if an offset repeats for n pixels starting one to
  // the right, it repeats for n + 1 here, so each is one comparison.
  for (var c = 0; c < cheapDistances.length; c++) {
    final dist = cheapDistances[c];
    final lengths = cheapLength[c];
    for (var i = numPixels - 1; i >= dist; i--) {
      if (px[i] == px[i - dist]) {
        var n = i + 1 < numPixels ? lengths[i + 1] + 1 : 1;
        final maxLen = numPixels - i;
        if (n > maxLen) {
          n = maxLen;
        }
        if (n > _maxMatchLen) {
          n = _maxMatchLen;
        }
        lengths[i] = n;
      }
    }
  }

  var i = numPixels - 1;
  while (i > 0) {
    var maxLen = numPixels - i;
    if (maxLen > _maxMatchLen) {
      maxLen = _maxMatchLen;
    }
    var best = 0;
    var bestDist = 0;

    // Two candidates cost nothing to try and are the cheapest distances the
    // format has, so they go first: either can leave the chain with nothing to
    // beat and be skipped entirely.
    for (var c = 0; c < cheapDistances.length; c++) {
      final n = cheapLength[c][i];
      if (n > best) {
        best = n;
        bestDist = cheapDistances[c];
      }
    }

    if (best < maxLen) {
      // Past a few hundred pixels a longer match saves almost nothing, so the
      // walk gives up rather than chasing the last few.
      final enough = maxLen < 256 ? maxLen : 256;
      var c = prev[i];
      var steps = 0;
      while (c >= 0 && steps < _maxChain) {
        steps++;
        final dist = i - c;
        if (dist > _maxDistance) {
          break;
        }
        // Only a longer match can win, so the pixel one past the current best
        // is a cheap rejection.
        if (px[c + best] == px[i + best]) {
          var len = 0;
          while (len < maxLen && px[i + len] == px[c + len]) {
            len++;
          }
          if (len > best) {
            best = len;
            bestDist = dist;
            if (best >= enough) {
              break;
            }
          }
        }
        c = prev[c];
      }
    }

    length[i] = best;
    distance[i] = bestDist;

    // Carry the match left for as long as it keeps matching.
    var j = i;
    while (bestDist > 0 && best < _maxMatchLen) {
      final k = j - 1;
      if (k <= 0 || k < bestDist || px[k - bestDist] != px[k]) {
        break;
      }
      best++;
      length[k] = best;
      distance[k] = bestDist;
      j = k;
    }
    i = j - 1;
  }
  return VP8LMatches(length, distance, cheapLength, cheapDistances);
}

/// Rebuilds the token stream from a parse that says, for each position, how
/// many pixels the token starting there covers.
///
/// A cover of 1 is a literal; anything longer is a back-reference at the
/// distance the parse chose for that position.
@internal
VP8LBackwardRefs refsFromCover(
    Int32List cover, Int32List coverDistance, int numPixels) {
  final isLiteral = <bool>[];
  final literalIndex = <int>[];
  final length = <int>[];
  final distance = <int>[];
  final positions = <int>[];
  var i = 0;
  while (i < numPixels) {
    final n = cover[i];
    positions.add(i);
    if (n <= 1) {
      isLiteral.add(true);
      literalIndex.add(i);
      i++;
    } else {
      isLiteral.add(false);
      length.add(n);
      distance.add(coverDistance[i]);
      i += n;
    }
  }
  return VP8LBackwardRefs(
      isLiteral, literalIndex, length, distance, Int32List.fromList(positions));
}

/// The hash chain the match search walks.
class _Lz77 {
  _Lz77(Uint8List r, Uint8List g, Uint8List b, Uint8List a, this._numPixels)
      : _px = Uint32List(_numPixels),
        _prev = Int32List(_numPixels) {
    var hashBits = 1;
    while ((1 << hashBits) < _numPixels && hashBits < 18) {
      hashBits++;
    }
    _shift = 64 - hashBits;
    _head = Int32List(1 << hashBits)..fillRange(0, 1 << hashBits, -1);

    // Pixels packed one word each, so matching compares a single value per
    // position instead of four, which is most of what this loop does.
    final px = _px;
    for (var i = 0; i < _numPixels; i++) {
      px[i] = (g[i] << 24) | (r[i] << 16) | (b[i] << 8) | a[i];
    }
  }

  final int _numPixels;
  final Uint32List _px;
  final Int32List _prev;
  late final Int32List _head;
  late final int _shift;

  /// The result of the last [findMatch]: length 0 means nothing matched.
  int matchLen = 0;
  int matchDist = 0;

  @pragma('vm:prefer-inline')
  int _hash(int high, int low) =>
      (((high << 32) | low) * 0x9e3779b97f4a7c15) >>> _shift;

  /// Links every position to the previous one that hashes the same.
  ///
  /// Positions are keyed on the pair of pixels starting there: one pixel alone
  /// puts far too many positions in a slot, and no match shorter than three
  /// pixels is ever coded, so keying on two loses nothing.
  ///
  /// libwebp keys a run of identical pixels on its colour and how much of it
  /// is left, to spread the run across slots. Tried here and reverted: it made
  /// the PNG suite 11% larger and the encode 36% slower. With a pair key, the
  /// most recent entry in a run's slot is the immediately preceding pixel, so
  /// the search finds a full-length match at distance 1 — the cheapest
  /// distance code there is — on its first step. Spreading the run replaces
  /// that with distant candidates. libwebp can afford it because it tries an
  /// RLE pass as a separate strategy.
  void fillChain() {
    final n = _numPixels;
    if (n <= 2) {
      return;
    }
    final px = _px;
    final prev = _prev;
    final head = _head;
    for (var pos = 0; pos < n - 1; pos++) {
      final h = _hash(px[pos], px[pos + 1]);
      prev[pos] = head[h];
      head[h] = pos;
    }
    // The last position starts no pair, so nothing links to it.
    prev[n - 1] = -1;
  }

  /// Longest match reaching back from [at], left in [matchLen]/[matchDist].
  void findMatch(int at) {
    matchLen = 0;
    matchDist = 0;
    final numPixels = _numPixels;
    if (at == 0 || at + 1 >= numPixels) {
      return;
    }
    final px = _px;
    final prev = _prev;
    final key = px[at];
    // Nothing past the end of the image can be part of a match, so the bound
    // is fixed for this position rather than retested every extension step.
    var maxLen = numPixels - at;
    if (maxLen > _maxMatchLen) {
      maxLen = _maxMatchLen;
    }
    var best = 0;
    var bestDist = 0;
    // The chain was built ahead of time, so this position's own link already
    // names the previous position that hashed the same.
    var c = prev[at];
    var steps = 0;
    while (c >= 0 && steps < _maxChain) {
      steps++;
      final dist = at - c;
      if (dist > _maxDistance) {
        break;
      }

      // Only a longer match than the best so far can win: the chain runs from
      // the most recent position backwards, so distance only ever grows and a
      // later candidate of equal length is never preferable. That makes the
      // pixel one past the current best a cheap rejection.
      if (px[c + best] == px[at + best] && px[c] == key) {
        var len = 1;
        while (len < maxLen && px[at + len] == px[c + len]) {
          len++;
        }
        if (len > best) {
          best = len;
          bestDist = dist;
          if (best >= maxLen) {
            break;
          }
        }
      }
      c = prev[c];
    }
    matchLen = best;
    matchDist = bestDist;
  }
}

/// What each symbol costs to code, in bits, estimated from a first pass over
/// the image.
///
/// The tokenizer has to choose between a match and a literal before any Huffman
/// code exists, so it works from the distribution a greedy pass produced. The
/// numbers are approximate, but they rank the choices far better than length
/// alone: a long match to a distant pixel can cost more than a short one near
/// by, and no length comparison sees that.
@internal
class VP8LCostModel {
  VP8LCostModel._(this._green, this._red, this._blue, this._alpha, this._dist);

  final Float64List _green;
  final Float64List _red;
  final Float64List _blue;
  final Float64List _alpha;
  final Float64List _dist;

  /// Builds the model straight from a cover of the image.
  ///
  /// Reading the cover rather than a built token stream keeps the first pass
  /// from materialising a list per token field only to throw it away.
  factory VP8LCostModel.fromCover(
      Int32List cover,
      Int32List coverDistance,
      Uint8List r,
      Uint8List g,
      Uint8List b,
      Uint8List a,
      int numPixels,
      int width) {
    final green = Float64List(280);
    final red = Float64List(256);
    final blue = Float64List(256);
    final alpha = Float64List(256);
    final dist = Float64List(40);

    var i = 0;
    while (i < numPixels) {
      final n = cover[i];
      if (n <= 1) {
        green[g[i]]++;
        red[r[i]]++;
        blue[b[i]]++;
        alpha[a[i]]++;
        i++;
      } else {
        green[huffman.lengthSymbol(n)]++;
        dist[huffman
            .prefixCode(huffman.distToPlaneCode(width, coverDistance[i]))]++;
        i += n;
      }
    }

    return VP8LCostModel._(_toBits(green), _toBits(red), _toBits(blue),
        _toBits(alpha), _toBits(dist));
  }

  /// Bits to code a match of each length, symbol and extra bits together.
  ///
  /// A parse that weighs every length at every position asks for this millions
  /// of times, and it depends on nothing but the length.
  late final Float64List lengthBits = () {
    final t = Float64List(_maxMatchLen + 1);
    for (var len = 1; len <= _maxMatchLen; len++) {
      final (extra, _) = huffman.lengthExtra(len);
      t[len] = _green[huffman.lengthSymbol(len)] + extra;
    }
    return t;
  }();

  /// Bits to code the distance part of a match at [distance].
  double distanceBits(int distance, int width) {
    final planeCode = huffman.distToPlaneCode(width, distance);
    final (extra, _) = huffman.prefixExtra(planeCode);
    return _dist[huffman.prefixCode(planeCode)] + extra;
  }

  /// Turns counts into bit costs. A symbol the first pass never used still has
  /// to be codeable, so it is charged as if it had appeared once.
  static Float64List _toBits(Float64List freq) {
    var total = 0.0;
    for (final f in freq) {
      total += f;
    }
    if (total == 0) {
      return Float64List(freq.length)..fillRange(0, freq.length, 8);
    }
    final bits = Float64List(freq.length);
    for (var i = 0; i < freq.length; i++) {
      final f = freq[i] > 0 ? freq[i] : 1.0;
      bits[i] = -(math.log(f / (total + 1)) / math.ln2);
    }
    return bits;
  }

  /// Bits to code the pixel at [i] as a literal.
  double literalCost(
          Uint8List r, Uint8List g, Uint8List b, Uint8List a, int i) =>
      _green[g[i]] + _red[r[i]] + _blue[b[i]] + _alpha[a[i]];
}

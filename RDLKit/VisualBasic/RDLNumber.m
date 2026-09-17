#import "RDLNumber.h"
#import "RDLExpression.h"
#import <math.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>

#pragma mark - Limits and messages

// How many significant digits .NET Framework writes a Double and a Single in
// when no format is given, and the exponent below which, as at or above the
// digit count, it switches to scientific notation.
static const int kRDLDoubleSignificantDigits = 15;
static const int kRDLSingleSignificantDigits = 7;
static const long kRDLLowestExponentWrittenScientific = -5;
// Room for "%.*e" of any double at those digits: sign, digits, point, exponent.
enum { kRDLScientificTextCapacity = 32 };

// The most places Math.Round takes for a Decimal and for a Double, and how
// large a Double can be before .NET leaves it as it is.
static const NSInteger kRDLDecimalRoundingDigitsLimit = 28;
static const NSInteger kRDLDoubleRoundingDigitsLimit = 15;
static const double kRDLDoubleRoundingMagnitudeLimit = 1e16;

NSString *RDLNumberFailureMessage(RDLNumberFailure failure) {
  switch (failure) {
  case RDLNumberFailureOverflow:
    return @"Arithmetic operation resulted in an overflow.";
  case RDLNumberFailureDivisionByZero:
    return @"Attempted to divide by zero.";
  case RDLNumberFailureNotANumber:
    return @"Function does not accept floating point Not-a-Number values.";
  case RDLNumberFailureDecimalRoundingDigits:
    return [NSString stringWithFormat:@"Rounding digits must be between 0 and %ld, inclusive.",
                                      (long)kRDLDecimalRoundingDigitsLimit];
  case RDLNumberFailureDoubleRoundingDigits:
    return [NSString stringWithFormat:@"Rounding digits must be between 0 and %ld, inclusive.",
                                      (long)kRDLDoubleRoundingDigitsLimit];
  case RDLNumberFailureInvalidFormatSpecifier:
    return @"Format specifier was invalid.";
  default:
    return @"";
  }
}

static void RDLFail(RDLNumberFailure *failure, RDLNumberFailure why) {
  if (failure)
    *failure = why;
}

#pragma mark - Wide whole numbers

// A whole number of up to 256 bits, least significant limb first: room for the
// product of two Decimal mantissas, or one scaled up by ten to the 28th, which
// is as wide as Decimal arithmetic gets before it rounds.
typedef unsigned __int128 RDLUInt128;
enum { kRDLWideLimbCount = 4 };
static const unsigned kRDLLimbBits = 64;

typedef struct {
  uint64_t limb[kRDLWideLimbCount];
} RDLWide;

// Ten to the powers that fit in one limb, 10^0 to 10^19.
static const uint64_t kRDLPowersOfTen[] = {
  1ULL, 10ULL, 100ULL, 1000ULL, 10000ULL, 100000ULL, 1000000ULL, 10000000ULL, 100000000ULL, 1000000000ULL,
  10000000000ULL, 100000000000ULL, 1000000000000ULL, 10000000000000ULL, 100000000000000ULL,
  1000000000000000ULL, 10000000000000000ULL, 100000000000000000ULL, 1000000000000000000ULL,
  10000000000000000000ULL,
};
static const unsigned kRDLLargestLimbPowerOfTen = 19;
static const uint64_t kRDLTen = 10;

static RDLWide RDLWideFrom128(RDLUInt128 v) {
  RDLWide w = {{(uint64_t)v, (uint64_t)(v >> kRDLLimbBits), 0, 0}};
  return w;
}

static RDLUInt128 RDLWideTo128(RDLWide w) {
  return ((RDLUInt128)w.limb[1] << kRDLLimbBits) | w.limb[0];
}

static BOOL RDLWideIsZero(RDLWide w) {
  return (w.limb[0] | w.limb[1] | w.limb[2] | w.limb[3]) == 0;
}

static int RDLWideCompare(RDLWide a, RDLWide b) {
  for (NSUInteger i = kRDLWideLimbCount; i-- > 0;) {
    if (a.limb[i] != b.limb[i])
      return a.limb[i] < b.limb[i] ? -1 : 1;
  }
  return 0;
}

static RDLWide RDLWideAdd(RDLWide a, RDLWide b) {
  RDLWide r = {{0, 0, 0, 0}};
  RDLUInt128 carry = 0;
  for (NSUInteger i = 0; i < kRDLWideLimbCount; i++) {
    carry += (RDLUInt128)a.limb[i] + b.limb[i];
    r.limb[i] = (uint64_t)carry;
    carry >>= kRDLLimbBits;
  }
  return r;
}

// a - b, for a no smaller than b.
static RDLWide RDLWideSubtract(RDLWide a, RDLWide b) {
  RDLWide r = {{0, 0, 0, 0}};
  uint64_t borrow = 0;
  for (NSUInteger i = 0; i < kRDLWideLimbCount; i++) {
    RDLUInt128 take = (RDLUInt128)b.limb[i] + borrow;
    borrow = (RDLUInt128)a.limb[i] < take ? 1 : 0;
    r.limb[i] = (uint64_t)((RDLUInt128)a.limb[i] - take);
  }
  return r;
}

static RDLWide RDLWideMultiplySmall(RDLWide a, uint64_t m) {
  RDLWide r = {{0, 0, 0, 0}};
  RDLUInt128 carry = 0;
  for (NSUInteger i = 0; i < kRDLWideLimbCount; i++) {
    carry += (RDLUInt128)a.limb[i] * m;
    r.limb[i] = (uint64_t)carry;
    carry >>= kRDLLimbBits;
  }
  return r;
}

// The product, kept to 256 bits; a Decimal's never needs more than 192.
static RDLWide RDLWideMultiply(RDLWide a, RDLWide b) {
  RDLWide r = {{0, 0, 0, 0}};
  for (NSUInteger i = 0; i < kRDLWideLimbCount; i++) {
    RDLUInt128 carry = 0;
    for (NSUInteger j = 0; i + j < kRDLWideLimbCount; j++) {
      carry += (RDLUInt128)a.limb[i] * b.limb[j] + r.limb[i + j];
      r.limb[i + j] = (uint64_t)carry;
      carry >>= kRDLLimbBits;
    }
  }
  return r;
}

// Divides in place by a one-limb divisor, and returns the remainder.
static uint64_t RDLWideDivideSmall(RDLWide *a, uint64_t d) {
  RDLUInt128 remainder = 0;
  for (NSUInteger i = kRDLWideLimbCount; i-- > 0;) {
    remainder = (remainder << kRDLLimbBits) | a->limb[i];
    a->limb[i] = (uint64_t)(remainder / d);
    remainder %= d;
  }
  return (uint64_t)remainder;
}

static NSUInteger RDLWideBitLength(RDLWide a) {
  for (NSUInteger i = kRDLWideLimbCount; i-- > 0;) {
    if (a.limb[i])
      return i * kRDLLimbBits + (kRDLLimbBits - (NSUInteger)__builtin_clzll(a.limb[i]));
  }
  return 0;
}

// Quotient and remainder of a by b, b not zero: shift and subtract, from a's
// highest bit.
static void RDLWideDivide(RDLWide a, RDLWide b, RDLWide *quotient, RDLWide *remainder) {
  RDLWide q = {{0, 0, 0, 0}}, r = {{0, 0, 0, 0}};
  for (NSUInteger bit = RDLWideBitLength(a); bit-- > 0;) {
    for (NSUInteger i = kRDLWideLimbCount - 1; i > 0; i--)
      r.limb[i] = (r.limb[i] << 1) | (r.limb[i - 1] >> (kRDLLimbBits - 1));
    r.limb[0] = (r.limb[0] << 1) | ((a.limb[bit / kRDLLimbBits] >> (bit % kRDLLimbBits)) & 1);
    if (RDLWideCompare(r, b) >= 0) {
      r = RDLWideSubtract(r, b);
      q.limb[bit / kRDLLimbBits] |= 1ULL << (bit % kRDLLimbBits);
    }
  }
  *quotient = q;
  *remainder = r;
}

static RDLWide RDLWideTimesPowerOfTen(RDLWide a, unsigned exponent) {
  while (exponent > 0) {
    unsigned step = MIN(exponent, kRDLLargestLimbPowerOfTen);
    a = RDLWideMultiplySmall(a, kRDLPowersOfTen[step]);
    exponent -= step;
  }
  return a;
}

// How places dropped from a whole number round what is kept.
typedef NS_ENUM(NSInteger, RDLDropRounding) {
  RDLDropRoundingUnspecified = 0,
  RDLDropRoundingToEven,
  RDLDropRoundingAwayFromZero,  // a half up, in magnitude
  RDLDropRoundingTowardZero,    // not at all
  RDLDropRoundingUp,            // up whenever anything was dropped, in magnitude
};

// `value` with its last `places` decimal digits dropped, rounded as asked;
// `sticky` says digits below those were dropped already and were not all zero.
static RDLWide RDLWideDropPlaces(RDLWide value, unsigned places, RDLDropRounding rounding, BOOL sticky) {
  if (places == 0)
    return value;
  unsigned rest = places - 1;
  while (rest > 0) {
    unsigned step = MIN(rest, kRDLLargestLimbPowerOfTen);
    sticky |= RDLWideDivideSmall(&value, kRDLPowersOfTen[step]) != 0;
    rest -= step;
  }
  uint64_t digit = RDLWideDivideSmall(&value, kRDLTen);
  const uint64_t half = kRDLTen / 2;
  BOOL up = NO;
  switch (rounding) {
  case RDLDropRoundingToEven:
    up = digit > half || (digit == half && (sticky || (value.limb[0] & 1)));
    break;
  case RDLDropRoundingAwayFromZero:
    up = digit >= half;
    break;
  case RDLDropRoundingUp:
    up = digit != 0 || sticky;
    break;
  default:
    break;
  }
  return up ? RDLWideAdd(value, RDLWideFrom128(1)) : value;
}

#pragma mark - .NET's Decimal

// System.Decimal: a 96-bit magnitude, 0 to 28 places after the point, a sign.
static const unsigned kRDLDecimalScaleLimit = 28;
static const unsigned kRDLDecimalMantissaBits = 96;
// A text's significant digits beyond this many are only noted as there: 10^76
// still fits in the 256 bits a wide number has.
static const NSUInteger kRDLParsedDigitsLimit = 76;
// An exponent in text past this is certainly an overflow, or certainly zero.
static const long kRDLParsedExponentLimit = 1000;

typedef struct {
  RDLUInt128 mantissa;
  unsigned scale;
  BOOL negative;
} RDLDecimal;

static BOOL RDLWideFitsDecimal(RDLWide w) {
  return RDLWideBitLength(w) <= kRDLDecimalMantissaBits;
}

// A magnitude at `scale` places made a Decimal as .NET makes a result one:
// places dropped, rounding to even, until there are at most 28 and the rest
// fits in 96 bits. NO when not even the whole part fits: the overflow.
static BOOL RDLDecimalFromWide(RDLWide magnitude, unsigned scale, BOOL negative, BOOL sticky, RDLDecimal *out) {
  unsigned drop = scale > kRDLDecimalScaleLimit ? scale - kRDLDecimalScaleLimit : 0;
  for (;;) {
    RDLWide kept = RDLWideDropPlaces(magnitude, drop, RDLDropRoundingToEven, sticky);
    if (RDLWideFitsDecimal(kept)) {
      out->mantissa = RDLWideTo128(kept);
      out->scale = scale - drop;
      out->negative = negative && out->mantissa != 0;
      return YES;
    }
    if (drop >= scale)
      return NO;
    drop += 1;
  }
}

static RDLDecimal RDLDecimalWithMagnitude(RDLUInt128 magnitude, BOOL negative) {
  RDLDecimal d = {magnitude, 0, negative && magnitude != 0};
  return d;
}

static RDLDecimal RDLDecimalWithLong(int64_t v) {
  // The magnitude of the smallest Long is one more than the largest.
  RDLUInt128 magnitude = v < 0 ? (RDLUInt128)(-(v + 1)) + 1 : (RDLUInt128)v;
  return RDLDecimalWithMagnitude(magnitude, v < 0);
}

static RDLWide RDLDecimalAligned(RDLDecimal d, unsigned scale) {
  return RDLWideTimesPowerOfTen(RDLWideFrom128(d.mantissa), scale - d.scale);
}

static RDLDecimal RDLDecimalWithoutTrailingZeros(RDLDecimal d);

static BOOL RDLDecimalAdd(RDLDecimal a, RDLDecimal b, RDLDecimal *out) {
  unsigned scale = MAX(a.scale, b.scale);
  RDLWide x = RDLDecimalAligned(a, scale), y = RDLDecimalAligned(b, scale);
  if (a.negative == b.negative)
    return RDLDecimalFromWide(RDLWideAdd(x, y), scale, a.negative, NO, out);
  if (RDLWideCompare(x, y) >= 0)
    return RDLDecimalFromWide(RDLWideSubtract(x, y), scale, a.negative, NO, out);
  return RDLDecimalFromWide(RDLWideSubtract(y, x), scale, b.negative, NO, out);
}

// The product at the operands' scales together: 1.000D * 1.000D is 1.000000.
// .NET multiplies two mantissas of 32 bits apart from wider ones, and the two
// ways part over a product of zero: the narrow way keeps its scale, 0.00D * 5D
// being 0.00, unless the places are past any rounding reaching them; the wide
// way makes it a plain 0.
static BOOL RDLDecimalMultiply(RDLDecimal a, RDLDecimal b, RDLDecimal *out) {
  unsigned scale = a.scale + b.scale;
  BOOL narrow = a.mantissa <= UINT32_MAX && b.mantissa <= UINT32_MAX;
  RDLWide product = RDLWideMultiply(RDLWideFrom128(a.mantissa), RDLWideFrom128(b.mantissa));
  if (narrow ? scale > kRDLDecimalScaleLimit + kRDLLargestLimbPowerOfTen : RDLWideIsZero(product)) {
    RDLDecimal zero = {0, 0, NO};
    *out = zero;
    return YES;
  }
  return RDLDecimalFromWide(product, scale, a.negative != b.negative, NO, out);
}

// As .NET divides: the whole quotient, then a digit at a time while the
// quotient still fits and has fewer than 28 places, the last one rounded to
// even by what remains. A quotient that took more places than the operands had
// loses the zeros ending it; an exact one keeps its scale. 1D / 3D has 28
// threes, 1.0D / 4D is 0.25, 10.00D / 4D is 2.50.
static RDLNumberFailure RDLDecimalDivide(RDLDecimal a, RDLDecimal b, RDLDecimal *out) {
  if (b.mantissa == 0)
    return RDLNumberFailureDivisionByZero;
  RDLWide divisor = RDLWideFrom128(b.mantissa), quotient, remainder;
  RDLWideDivide(RDLWideFrom128(a.mantissa), divisor, &quotient, &remainder);
  int scale = (int)a.scale - (int)b.scale;
  BOOL inexact = NO;
  while (scale < 0 || (!RDLWideIsZero(remainder) && scale < (int)kRDLDecimalScaleLimit)) {
    inexact |= !RDLWideIsZero(remainder);
    RDLWide digit, rest;
    RDLWideDivide(RDLWideMultiplySmall(remainder, kRDLTen), divisor, &digit, &rest);
    RDLWide longer = RDLWideAdd(RDLWideMultiplySmall(quotient, kRDLTen), digit);
    if (!RDLWideFitsDecimal(longer)) {
      if (scale < 0)
        return RDLNumberFailureOverflow;
      break;
    }
    quotient = longer;
    remainder = rest;
    scale += 1;
  }
  if (!RDLWideIsZero(remainder)) {
    inexact = YES;
    // What remains against what the divisor still lacks: more is past half.
    int half = RDLWideCompare(remainder, RDLWideSubtract(divisor, remainder));
    if (half > 0 || (half == 0 && (quotient.limb[0] & 1)))
      quotient = RDLWideAdd(quotient, RDLWideFrom128(1));
  }
  if (!RDLDecimalFromWide(quotient, (unsigned)scale, a.negative != b.negative, NO, out))
    return RDLNumberFailureOverflow;
  if (inexact)
    *out = RDLDecimalWithoutTrailingZeros(*out);
  return RDLNumberFailureUnspecified;
}

// .NET's %: what is left of the dividend, with its sign, at the larger scale
// -- but a dividend smaller than the divisor is what is left, scale and all.
static RDLNumberFailure RDLDecimalModulo(RDLDecimal a, RDLDecimal b, RDLDecimal *out) {
  if (b.mantissa == 0)
    return RDLNumberFailureDivisionByZero;
  unsigned scale = MAX(a.scale, b.scale);
  RDLWide dividend = RDLDecimalAligned(a, scale), divisor = RDLDecimalAligned(b, scale);
  if (RDLWideCompare(dividend, divisor) < 0) {
    *out = a;
    return RDLNumberFailureUnspecified;
  }
  RDLWide quotient, remainder;
  RDLWideDivide(dividend, divisor, &quotient, &remainder);
  return RDLDecimalFromWide(remainder, scale, a.negative, NO, out) ? RDLNumberFailureUnspecified
                                                                  : RDLNumberFailureOverflow;
}

static NSComparisonResult RDLDecimalCompare(RDLDecimal a, RDLDecimal b) {
  BOOL aNegative = a.negative && a.mantissa != 0, bNegative = b.negative && b.mantissa != 0;
  if (a.mantissa == 0 && b.mantissa == 0)
    return NSOrderedSame;
  if (aNegative != bNegative)
    return aNegative ? NSOrderedAscending : NSOrderedDescending;
  unsigned scale = MAX(a.scale, b.scale);
  int c = RDLWideCompare(RDLDecimalAligned(a, scale), RDLDecimalAligned(b, scale));
  if (aNegative)
    c = -c;
  return c < 0 ? NSOrderedAscending : c > 0 ? NSOrderedDescending : NSOrderedSame;
}

// To at most `places` places; a Decimal with fewer keeps them all.
static RDLDecimal RDLDecimalRounded(RDLDecimal d, unsigned places, RDLDropRounding rounding) {
  if (d.scale <= places)
    return d;
  RDLWide kept = RDLWideDropPlaces(RDLWideFrom128(d.mantissa), d.scale - places, rounding, NO);
  d.mantissa = RDLWideTo128(kept);
  d.scale = places;
  d.negative = d.negative && d.mantissa != 0;
  return d;
}

// Floor, Ceiling or Truncate, to no places at all.
static RDLDecimal RDLDecimalWhole(RDLDecimal d, RDLWholeRounding rounding) {
  RDLDropRounding drop = RDLDropRoundingTowardZero;
  if (rounding == RDLWholeRoundingFloor && d.negative)
    drop = RDLDropRoundingUp;
  if (rounding == RDLWholeRoundingCeiling && !d.negative)
    drop = RDLDropRoundingUp;
  return RDLDecimalRounded(d, 0, drop);
}

// The same value with no zeros ending its places: what .NET makes of a
// Double taken into a Decimal.
static RDLDecimal RDLDecimalWithoutTrailingZeros(RDLDecimal d) {
  while (d.scale > 0 && d.mantissa % kRDLTen == 0) {
    d.mantissa /= kRDLTen;
    d.scale -= 1;
  }
  return d;
}

static double RDLDecimalDouble(RDLDecimal d) {
  double magnitude = (double)d.mantissa / pow((double)kRDLTen, (double)d.scale);
  return d.negative ? -magnitude : magnitude;
}

// Room for the digits of any 96-bit magnitude, and more.
enum { kRDLMagnitudeDigitsCapacity = 48 };

static NSString *RDLDecimalMagnitudeDigits(RDLUInt128 m) {
  char buffer[kRDLMagnitudeDigitsCapacity];
  size_t at = sizeof buffer - 1;
  buffer[at] = '\0';
  do {
    buffer[--at] = (char)('0' + (int)(m % kRDLTen));
    m /= kRDLTen;
  } while (m);
  return [NSString stringWithUTF8String:buffer + at];
}

// The digits with the point where the scale puts it, and a sign when it is
// not zero: 1.10, -0.05, 100.
static NSString *RDLDecimalText(RDLDecimal d) {
  NSString *digits = RDLDecimalMagnitudeDigits(d.mantissa);
  if (d.scale > 0) {
    if ([digits length] <= d.scale)
      digits = [[@"" stringByPaddingToLength:d.scale + 1 - [digits length] withString:@"0" startingAtIndex:0]
          stringByAppendingString:digits];
    NSUInteger point = [digits length] - d.scale;
    digits = [NSString stringWithFormat:@"%@.%@", [digits substringToIndex:point], [digits substringFromIndex:point]];
  }
  return d.negative && d.mantissa != 0 ? [@"-" stringByAppendingString:digits] : digits;
}

typedef NS_ENUM(NSInteger, RDLDecimalParse) {
  RDLDecimalParseUnspecified = 0,
  RDLDecimalParseNumber,
  RDLDecimalParseNotANumber,
  RDLDecimalParseOverflow,
};

// Text as a Decimal, exactly: a sign, digits, a point, an exponent, spaces
// around; digits past 28 places rounded to even, as .NET reads one.
static RDLDecimalParse RDLDecimalFromText(NSString *text, RDLDecimal *out) {
  NSString *t = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  NSUInteger n = [t length], i = 0;
  BOOL negative = NO;
  if (i < n && ([t characterAtIndex:i] == '-' || [t characterAtIndex:i] == '+'))
    negative = [t characterAtIndex:i++] == '-';
  RDLWide magnitude = {{0, 0, 0, 0}};
  NSUInteger kept = 0, digits = 0;
  long exponent = 0;
  BOOL sticky = NO, point = NO;
  for (; i < n; i++) {
    unichar c = [t characterAtIndex:i];
    if (c == '.' && !point) {
      point = YES;
      continue;
    }
    if (c < '0' || c > '9')
      break;
    digits += 1;
    if (kept == 0 && c == '0') {
      if (point)
        exponent -= 1;
      continue;
    }
    if (kept < kRDLParsedDigitsLimit) {
      magnitude = RDLWideAdd(RDLWideMultiplySmall(magnitude, kRDLTen), RDLWideFrom128((RDLUInt128)(c - '0')));
      kept += 1;
      if (point)
        exponent -= 1;
    } else {
      sticky |= c != '0';
      if (!point)
        exponent += 1;
    }
  }
  if (digits == 0)
    return RDLDecimalParseNotANumber;
  if (i < n && ([t characterAtIndex:i] == 'e' || [t characterAtIndex:i] == 'E')) {
    i += 1;
    BOOL negativeExponent = NO;
    if (i < n && ([t characterAtIndex:i] == '-' || [t characterAtIndex:i] == '+'))
      negativeExponent = [t characterAtIndex:i++] == '-';
    long written = 0;
    NSUInteger start = i;
    for (; i < n && [t characterAtIndex:i] >= '0' && [t characterAtIndex:i] <= '9'; i++)
      written = MIN(written * (long)kRDLTen + ([t characterAtIndex:i] - '0'), kRDLParsedExponentLimit);
    if (i == start)
      return RDLDecimalParseNotANumber;
    exponent += negativeExponent ? -written : written;
  }
  if (i != n)
    return RDLDecimalParseNotANumber;
  if (RDLWideIsZero(magnitude)) {
    unsigned scale = exponent < 0 ? (unsigned)MIN(-exponent, (long)kRDLDecimalScaleLimit) : 0;
    RDLDecimal zero = {0, scale, NO};
    *out = zero;
    return RDLDecimalParseNumber;
  }
  if (exponent > 0) {
    if (exponent > (long)(kRDLParsedDigitsLimit - kept))
      return RDLDecimalParseOverflow;
    magnitude = RDLWideTimesPowerOfTen(magnitude, (unsigned)exponent);
    exponent = 0;
  }
  unsigned scale = (unsigned)(-exponent);
  // So far below the smallest place that nothing of it survives rounding.
  if (scale > kRDLDecimalScaleLimit + kRDLParsedDigitsLimit) {
    RDLDecimal zero = {0, kRDLDecimalScaleLimit, NO};
    *out = zero;
    return RDLDecimalParseNumber;
  }
  return RDLDecimalFromWide(magnitude, scale, negative, sticky, out) ? RDLDecimalParseNumber : RDLDecimalParseOverflow;
}

// The significant digits .NET keeps of a Double and of a Single it takes into
// a Decimal, and the binary exponents past which one is too small to leave
// anything or too large to fit.
static const int kRDLDoubleDecimalDigits = 15;
static const int kRDLSingleDecimalDigits = 7;
static const int kRDLDoubleBelowDecimal = -94;
static const int kRDLSingleBelowDecimal = -95;
static const int kRDLAboveDecimal = 96;
// log10(2) as a 16-bit fraction, for guessing a power of ten from a binary
// exponent the way .NET does.
static const int kRDLLog10Of2Fraction = 19728;
static const int kRDLLog10Of2Shift = 16;
// The powers of ten .NET scales by, as the Doubles its table writes them; a
// computed pow() need not land on the same ones.
static const double kRDLDoublePowersOfTen[] = {
  1e0,  1e1,  1e2,  1e3,  1e4,  1e5,  1e6,  1e7,  1e8,  1e9,  1e10, 1e11, 1e12, 1e13, 1e14,
  1e15, 1e16, 1e17, 1e18, 1e19, 1e20, 1e21, 1e22, 1e23, 1e24, 1e25, 1e26, 1e27, 1e28,
};

// A Double or a Single into a Decimal as .NET's VarDecFromR8 and VarDecFromR4
// take one: scaled by a power of ten, as a Double, to a whole number of 15 or 7
// digits, rounded to even there, then the zeros ending it taken back out of the
// scale. That scaling is binary arithmetic, so the last digit is .NET's and not
// always the correctly rounded one: CDec(661777.4807356275) is 661777.480735628.
static RDLNumberFailure RDLDecimalFromDouble(double input, BOOL single, RDLDecimal *out) {
  if (!isfinite(input))
    return RDLNumberFailureOverflow;
  int digits = single ? kRDLSingleDecimalDigits : kRDLDoubleDecimalDigits;
  // The exponent .NET reads off the bits is frexp's: 1 for 1.0.
  int exponent = 0;
  frexp(input, &exponent);
  if (exponent < (single ? kRDLSingleBelowDecimal : kRDLDoubleBelowDecimal) || input == 0) {
    RDLDecimal zero = {0, 0, NO};
    *out = zero;
    return RDLNumberFailureUnspecified;
  }
  if (exponent > kRDLAboveDecimal)
    return RDLNumberFailureOverflow;
  double value = fabs(input);
  double limit = kRDLDoublePowersOfTen[digits], floor = kRDLDoublePowersOfTen[digits - 1];
  int power = (digits - 1) - ((exponent * kRDLLog10Of2Fraction) >> kRDLLog10Of2Shift);
  if (power >= 0) {
    power = MIN(power, (int)kRDLDecimalScaleLimit);
    value *= kRDLDoublePowersOfTen[power];
  } else if (power != -1 || value >= limit) {
    value /= kRDLDoublePowersOfTen[-power];
  } else {
    power = 0;
  }
  if (value < floor && power < (int)kRDLDecimalScaleLimit) {
    value *= (double)kRDLTen;
    power += 1;
  }
  uint64_t mantissa = (uint64_t)(int64_t)value;
  double fraction = value - (double)(int64_t)mantissa;
  const double half = 0.5;
  if (fraction > half || (fraction == half && (mantissa & 1)))
    mantissa += 1;
  if (mantissa == 0) {
    RDLDecimal zero = {0, 0, NO};
    *out = zero;
    return RDLNumberFailureUnspecified;
  }
  RDLDecimal d = {mantissa, 0, input < 0};
  if (power < 0) {
    RDLWide scaled = RDLWideTimesPowerOfTen(RDLWideFrom128(mantissa), (unsigned)-power);
    if (!RDLWideFitsDecimal(scaled))
      return RDLNumberFailureOverflow;
    d.mantissa = RDLWideTo128(scaled);
  } else {
    // Only as many zeros as the digits allow can be factored out, and never
    // more than the power put in.
    unsigned most = (unsigned)MIN(power, digits - 1);
    d.scale = (unsigned)power;
    while (most > 0 && d.mantissa % kRDLTen == 0) {
      d.mantissa /= kRDLTen;
      d.scale -= 1;
      most -= 1;
    }
  }
  *out = d;
  return RDLNumberFailureUnspecified;
}

#pragma mark - Text of a Double

// A Double or a Single as .NET Framework writes one with no format: rounded
// to its significant digits, trailing zeros dropped, and 1E-05 or 1.5E+20 when
// the exponent is at most -5 or at least the digit count. CStr(0.1 + 0.2) is
// "0.3" there.
static NSString *RDLGeneralNumberText(double d, int digits) {
  if (isnan(d))
    return @"NaN";
  if (isinf(d))
    return d > 0 ? @"Infinity" : @"-Infinity";
  if (d == 0)
    return @"0";
  char buffer[kRDLScientificTextCapacity];
  snprintf(buffer, sizeof buffer, "%.*e", digits - 1, fabs(d));
  NSString *scientific = [NSString stringWithUTF8String:buffer];
  NSRange e = [scientific rangeOfString:@"e"];
  long exponent = [[scientific substringFromIndex:e.location + 1] integerValue];
  NSString *figures = [[scientific substringToIndex:e.location] stringByReplacingOccurrencesOfString:@"."
                                                                                           withString:@""];
  NSUInteger end = [figures length];
  while (end > 1 && [figures characterAtIndex:end - 1] == '0')
    end -= 1;
  figures = [figures substringToIndex:end];
  NSString *sign = d < 0 ? @"-" : @"";
  if (exponent > kRDLLowestExponentWrittenScientific && exponent < digits) {
    if (exponent < 0) {
      NSString *zeros = [@"" stringByPaddingToLength:(NSUInteger)(-exponent - 1) withString:@"0" startingAtIndex:0];
      return [NSString stringWithFormat:@"%@0.%@%@", sign, zeros, figures];
    }
    NSUInteger whole = (NSUInteger)exponent + 1;
    if ([figures length] <= whole) {
      NSString *zeros = [@"" stringByPaddingToLength:whole - [figures length] withString:@"0" startingAtIndex:0];
      return [NSString stringWithFormat:@"%@%@%@", sign, figures, zeros];
    }
    return [NSString stringWithFormat:@"%@%@.%@", sign, [figures substringToIndex:whole],
                                      [figures substringFromIndex:whole]];
  }
  NSString *fraction = [figures length] > 1 ? [@"." stringByAppendingString:[figures substringFromIndex:1]] : @"";
  return [NSString stringWithFormat:@"%@%@%@E%@%02ld", sign, [figures substringToIndex:1], fraction,
                                    exponent < 0 ? @"-" : @"+", labs(exponent)];
}

#pragma mark - .NET's number formats

// A standard number format's letter: C, D, E, F, G, N, P, R or X. Unsupported
// is a letter and digits that .NET does not know, which it refuses.
typedef NS_ENUM(NSInteger, RDLNumberFormatKind) {
  RDLNumberFormatKindUnspecified = 0,
  RDLNumberFormatKindCurrency,
  RDLNumberFormatKindDecimal,
  RDLNumberFormatKindExponent,
  RDLNumberFormatKindFixed,
  RDLNumberFormatKindGeneral,
  RDLNumberFormatKindNumber,
  RDLNumberFormatKindPercent,
  RDLNumberFormatKindRoundTrip,
  RDLNumberFormatKindHexadecimal,
  RDLNumberFormatKindUnsupported,
};

// A standard format is a letter and at most two digits of precision.
static const NSUInteger kRDLStandardFormatLengthLimit = 3;
// The decimals .NET gives N, F and P, and E, when none are asked for; the
// currency's own come from the culture.
static const NSInteger kRDLDefaultNumberDecimalDigits = 2;
static const NSInteger kRDLDefaultPercentDecimalDigits = 2;
static const NSInteger kRDLDefaultExponentDecimalDigits = 6;
// How many digits an exponent has at least: E+003 in E, E+03 in G and R.
static const NSUInteger kRDLExponentFormatDigits = 3;
static const NSUInteger kRDLGeneralExponentDigits = 2;
// A percentage is the number a hundred times over: its point two places on.
static const NSInteger kRDLPercentScalePlaces = 2;
static const NSInteger kRDLDefaultGroupSize = 3;
// G's precision when none is given, by type, as .NET has it.
static const NSInteger kRDLShortGeneralDigits = 5;
static const NSInteger kRDLIntegerGeneralDigits = 10;
static const NSInteger kRDLLongGeneralDigits = 19;
static const NSInteger kRDLDecimalGeneralDigits = 29;
// The digits a Double and a Single are taken to where 15 and 7 are too few:
// R when those do not read back as the same number, and E and G asking for more.
static const NSInteger kRDLDoubleRoundTripDigits = 17;
static const NSInteger kRDLSingleRoundTripDigits = 9;
// The places FormatNumber and the others take when asked for the culture's.
static const NSInteger kRDLCultureDigits = -1;

static RDLNumberFormatKind RDLStandardNumberFormat(NSString *format, BOOL *upper, NSInteger *precision) {
  NSUInteger length = [format length];
  if (length == 0 || length > kRDLStandardFormatLengthLimit)
    return RDLNumberFormatKindUnspecified;
  unichar letter = [format characterAtIndex:0];
  if (!((letter >= 'A' && letter <= 'Z') || (letter >= 'a' && letter <= 'z')))
    return RDLNumberFormatKindUnspecified;
  for (NSUInteger i = 1; i < length; i++) {
    unichar c = [format characterAtIndex:i];
    if (c < '0' || c > '9')
      return RDLNumberFormatKindUnspecified;
  }
  *upper = letter >= 'A' && letter <= 'Z';
  *precision = length > 1 ? [[format substringFromIndex:1] integerValue] : -1;
  switch (letter | 0x20) {
  case 'c':
    return RDLNumberFormatKindCurrency;
  case 'd':
    return RDLNumberFormatKindDecimal;
  case 'e':
    return RDLNumberFormatKindExponent;
  case 'f':
    return RDLNumberFormatKindFixed;
  case 'g':
    return RDLNumberFormatKindGeneral;
  case 'n':
    return RDLNumberFormatKindNumber;
  case 'p':
    return RDLNumberFormatKindPercent;
  case 'r':
    return RDLNumberFormatKindRoundTrip;
  case 'x':
    return RDLNumberFormatKindHexadecimal;
  default:
    return RDLNumberFormatKindUnsupported;
  }
}

@implementation RDLNumberCulture

static NSNumberFormatter *RDLFormatterInStyle(NSLocale *locale, NSNumberFormatterStyle style) {
  NSNumberFormatter *f = [[NSNumberFormatter alloc] init];
  [f setFormatterBehavior:NSNumberFormatterBehavior10_4];
  f.locale = locale;
  f.numberStyle = style;
  return f;
}

// The minor units of an ISO 4217 currency -- the digits after the point a
// currency amount is written with. Cocoa's currency NSNumberFormatter reports
// this as its fraction digits; GNUstep's reports 0 for every currency and
// gives no pattern to read it from, so it is derived from the currency code.
// Two, but for the currencies that have none or three (the four-digit ones are
// funds, not cash, and do not arise here).
static NSInteger RDLCurrencyMinorUnits(NSString *code) {
  static NSSet *zero, *three;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    zero = [NSSet setWithArray:@[ @"BIF", @"CLP", @"DJF", @"GNF", @"ISK", @"JPY", @"KMF", @"KRW", @"PYG", @"RWF",
                                  @"UGX", @"VND", @"VUV", @"XAF", @"XOF", @"XPF" ]];
    three = [NSSet setWithArray:@[ @"BHD", @"IQD", @"JOD", @"KWD", @"LYD", @"OMR", @"TND" ]];
  });
  NSString *c = [code uppercaseString] ?: @"";
  if ([zero containsObject:c])
    return 0;
  if ([three containsObject:c])
    return 3;
  return 2;
}

+ (instancetype)cultureForLocale:(NSLocale *)locale {
  RDLNumberCulture *c = [[self alloc] init];
  NSNumberFormatter *decimal = RDLFormatterInStyle(locale, NSNumberFormatterDecimalStyle);
  c.decimalSeparator = [decimal.decimalSeparator length] ? decimal.decimalSeparator : @".";
  c.groupSeparator = decimal.groupingSeparator ?: @",";
  c.minusSign = [decimal.minusSign length] ? decimal.minusSign : @"-";
  c.plusSign = [decimal.plusSign length] ? decimal.plusSign : @"+";
  c.groupSize = decimal.groupingSize > 0 ? (NSInteger)decimal.groupingSize : kRDLDefaultGroupSize;
  c.secondaryGroupSize = (NSInteger)decimal.secondaryGroupingSize;
  NSNumberFormatter *currency = RDLFormatterInStyle(locale, NSNumberFormatterCurrencyStyle);
  c.currencySymbol = currency.currencySymbol ?: @"¤";
  // GNUstep's currency formatter reports 0 fraction digits and no pattern for
  // every currency; when it gives no pattern to trust, take the digits from
  // the currency code instead. (Cocoa gives a real pattern, so it is used.)
  c.currencyDigits = [currency.positiveFormat length]
                         ? (NSInteger)currency.maximumFractionDigits
                         : RDLCurrencyMinorUnits([locale objectForKey:NSLocaleCurrencyCode]);
  c.currencyPattern = [currency.positiveFormat length] ? currency.positiveFormat : @"¤#,##0.00";
  c.currencyNegativePattern = [currency.negativeFormat length] ? currency.negativeFormat
                                                               : [@"-" stringByAppendingString:c.currencyPattern];
  NSNumberFormatter *percent = RDLFormatterInStyle(locale, NSNumberFormatterPercentStyle);
  c.percentSymbol = percent.percentSymbol ?: @"%";
  c.perMilleSymbol = [percent.perMillSymbol length] ? percent.perMillSymbol : @"‰";
  c.percentPattern = [percent.positiveFormat length] ? percent.positiveFormat : @"#,##0%";
  c.percentNegativePattern = [percent.negativeFormat length] ? percent.negativeFormat
                                                             : [@"-" stringByAppendingString:c.percentPattern];
  return c;
}

- (id)copyWithZone:(NSZone *)zone {
  RDLNumberCulture *c = [[RDLNumberCulture allocWithZone:zone] init];
  c.decimalSeparator = self.decimalSeparator;
  c.groupSeparator = self.groupSeparator;
  c.minusSign = self.minusSign;
  c.plusSign = self.plusSign;
  c.currencySymbol = self.currencySymbol;
  c.percentSymbol = self.percentSymbol;
  c.perMilleSymbol = self.perMilleSymbol;
  c.currencyPattern = self.currencyPattern;
  c.currencyNegativePattern = self.currencyNegativePattern;
  c.percentPattern = self.percentPattern;
  c.percentNegativePattern = self.percentNegativePattern;
  c.currencyDigits = self.currencyDigits;
  c.groupSize = self.groupSize;
  c.secondaryGroupSize = self.secondaryGroupSize;
  return c;
}

@end

// A number as the digits formatting works on: its significant figures, with no
// zeros leading or trailing (none at all for zero), how many of them come
// before the decimal point -- which may be none, or more than there are -- and
// its sign. 1234.5 is "12345" with the point after 4; 0.05 is "5" with it at -1.
@interface RDLFormatDigits : NSObject
@property (nonatomic) BOOL negative;
@property (nonatomic, copy) NSString *figures;
@property (nonatomic) NSInteger point;
@end

@implementation RDLFormatDigits
@end

static NSString *RDLZeros(NSInteger count) {
  return count > 0 ? [@"" stringByPaddingToLength:(NSUInteger)count withString:@"0" startingAtIndex:0] : @"";
}

// Plain digits with a point, "0012.50", as figures.
static RDLFormatDigits *RDLDigitsFromText(NSString *text, BOOL negative) {
  NSRange dot = [text rangeOfString:@"."];
  NSString *whole = dot.location == NSNotFound ? text : [text substringToIndex:dot.location];
  NSString *all = dot.location == NSNotFound ? text : [whole stringByAppendingString:[text substringFromIndex:dot.location + 1]];
  NSInteger point = (NSInteger)[whole length];
  NSUInteger start = 0, end = [all length];
  while (start < end && [all characterAtIndex:start] == '0') {
    start += 1;
    point -= 1;
  }
  while (end > start && [all characterAtIndex:end - 1] == '0')
    end -= 1;
  RDLFormatDigits *d = [[RDLFormatDigits alloc] init];
  d.figures = [all substringWithRange:NSMakeRange(start, end - start)];
  d.point = [d.figures length] ? point : 0;
  d.negative = negative && [d.figures length] > 0;
  return d;
}

// A number's figures: a whole number's and a Decimal's exactly, a Double's or
// a Single's to `significant` digits.
static RDLFormatDigits *RDLDigitsOfNumber(RDLNumber *n, NSInteger significant) {
  if ([n isFloatingPoint]) {
    double v = [n doubleValue];
    char buffer[kRDLScientificTextCapacity];
    snprintf(buffer, sizeof buffer, "%.*e", (int)significant - 1, fabs(v));
    NSString *text = [NSString stringWithUTF8String:buffer];
    NSRange e = [text rangeOfString:@"e"];
    RDLFormatDigits *d = RDLDigitsFromText([text substringToIndex:e.location], v < 0);
    if ([d.figures length])
      d.point += [[text substringFromIndex:e.location + 1] integerValue];
    return d;
  }
  NSString *text = [n description];
  BOOL negative = [text hasPrefix:@"-"];
  return RDLDigitsFromText(negative ? [text substringFromIndex:1] : text, negative);
}

// The figures rounded to keep `keep` of them, halves away from zero, as .NET
// rounds for formatting. Keeping fewer than none leaves zero.
static RDLFormatDigits *RDLDigitsRounded(RDLFormatDigits *d, NSInteger keep) {
  NSUInteger length = [d.figures length];
  if (keep >= (NSInteger)length)
    return d;
  RDLFormatDigits *r = [[RDLFormatDigits alloc] init];
  r.negative = d.negative;
  r.point = d.point;
  NSMutableString *kept = [NSMutableString string];
  if (keep >= 0) {
    [kept appendString:[d.figures substringToIndex:(NSUInteger)keep]];
    if ([d.figures characterAtIndex:(NSUInteger)keep] >= '5') {
      NSInteger i = keep - 1;
      while (i >= 0 && [kept characterAtIndex:(NSUInteger)i] == '9') {
        [kept replaceCharactersInRange:NSMakeRange((NSUInteger)i, 1) withString:@"0"];
        i -= 1;
      }
      if (i >= 0) {
        unichar next = (unichar)([kept characterAtIndex:(NSUInteger)i] + 1);
        [kept replaceCharactersInRange:NSMakeRange((NSUInteger)i, 1) withString:[NSString stringWithCharacters:&next length:1]];
      } else {
        [kept insertString:@"1" atIndex:0];
        r.point += 1;
      }
    }
  }
  NSUInteger end = [kept length];
  while (end > 0 && [kept characterAtIndex:end - 1] == '0')
    end -= 1;
  r.figures = [kept substringToIndex:end];
  if ([r.figures length] == 0) {
    r.negative = NO;
    r.point = 0;
  }
  return r;
}

static NSString *RDLWholeFigures(RDLFormatDigits *d) {
  NSUInteger length = [d.figures length];
  if (d.point <= 0)
    return @"0";
  if ((NSUInteger)d.point >= length)
    return [d.figures stringByAppendingString:RDLZeros(d.point - (NSInteger)length)];
  return [d.figures substringToIndex:(NSUInteger)d.point];
}

// Every figure after the point, with the zeros before the first of them.
static NSString *RDLFractionFigures(RDLFormatDigits *d) {
  NSUInteger length = [d.figures length];
  if (length == 0)
    return @"";
  if (d.point <= 0)
    return [RDLZeros(-d.point) stringByAppendingString:d.figures];
  return (NSUInteger)d.point >= length ? @"" : [d.figures substringFromIndex:(NSUInteger)d.point];
}

static NSString *RDLGrouped(NSString *whole, RDLNumberCulture *c) {
  NSMutableArray<NSString *> *groups = [NSMutableArray array];
  NSInteger end = (NSInteger)[whole length], size = c.groupSize;
  while (size > 0 && end > size) {
    [groups insertObject:[whole substringWithRange:NSMakeRange((NSUInteger)(end - size), (NSUInteger)size)] atIndex:0];
    end -= size;
    if (c.secondaryGroupSize > 0)
      size = c.secondaryGroupSize;
  }
  [groups insertObject:[whole substringToIndex:(NSUInteger)end] atIndex:0];
  return [groups componentsJoinedByString:c.groupSeparator];
}

// The figures in fixed notation to exactly `decimals` places, grouped or not.
static NSString *RDLFixedFigures(RDLFormatDigits *d, NSInteger decimals, BOOL grouped, RDLNumberCulture *c) {
  NSString *whole = grouped ? RDLGrouped(RDLWholeFigures(d), c) : RDLWholeFigures(d);
  if (decimals <= 0)
    return whole;
  NSString *fraction = RDLFractionFigures(d);
  fraction = (NSInteger)[fraction length] >= decimals ? [fraction substringToIndex:(NSUInteger)decimals]
                                                      : [fraction stringByAppendingString:RDLZeros(decimals - (NSInteger)[fraction length])];
  return [NSString stringWithFormat:@"%@%@%@", whole, c.decimalSeparator, fraction];
}

// d.ddd: the first figure and the rest, padded to `decimals` or as they are.
static NSString *RDLMantissaFigures(RDLFormatDigits *d, NSInteger decimals, BOOL padded, RDLNumberCulture *c) {
  NSString *figures = [d.figures length] ? d.figures : @"0";
  NSString *rest = [figures substringFromIndex:1];
  if (padded)
    rest = (NSInteger)[rest length] >= decimals ? [rest substringToIndex:(NSUInteger)decimals]
                                                : [rest stringByAppendingString:RDLZeros(decimals - (NSInteger)[rest length])];
  return [rest length] ? [NSString stringWithFormat:@"%@%@%@", [figures substringToIndex:1], c.decimalSeparator, rest]
                       : [figures substringToIndex:1];
}

static NSString *RDLExponentFigures(NSInteger exponent, BOOL upper, NSUInteger minimumDigits, RDLNumberCulture *c) {
  NSString *digits = [NSString stringWithFormat:@"%ld", labs((long)exponent)];
  return [NSString stringWithFormat:@"%@%@%@%@", upper ? @"E" : @"e", exponent < 0 ? c.minusSign : c.plusSign,
                                    RDLZeros((NSInteger)minimumDigits - (NSInteger)[digits length]), digits];
}

// G's way of writing figures: fixed notation while the exponent is above -5
// and below the precision, 1.5E+20 otherwise.
static NSString *RDLGeneralFigures(RDLFormatDigits *d, NSInteger precision, BOOL upper, RDLNumberCulture *c) {
  NSInteger exponent = [d.figures length] ? d.point - 1 : 0;
  if (exponent > kRDLLowestExponentWrittenScientific && exponent < precision) {
    NSString *fraction = RDLFractionFigures(d);
    NSString *whole = RDLWholeFigures(d);
    return [fraction length] ? [NSString stringWithFormat:@"%@%@%@", whole, c.decimalSeparator, fraction] : whole;
  }
  return [RDLMantissaFigures(d, 0, NO, c) stringByAppendingString:RDLExponentFigures(exponent, upper, kRDLGeneralExponentDigits, c)];
}

static NSString *RDLSigned(NSString *text, BOOL negative, RDLNumberCulture *c) {
  return negative ? [c.minusSign stringByAppendingString:text] : text;
}

// Figures put in one of the culture's patterns as the platform writes them --
// "¤#,##0.00", "#,##0.00 ¤", "-¤#,##0.00", "#,##0 %" -- with the culture's
// symbols where the pattern has their placeholders.
static NSString *RDLInPattern(NSString *pattern, NSString *figures, BOOL negative, RDLNumberCulture *c) {
  NSCharacterSet *placeholders = [NSCharacterSet characterSetWithCharactersInString:@"#0"];
  NSRange first = [pattern rangeOfCharacterFromSet:placeholders];
  NSRange last = [pattern rangeOfCharacterFromSet:placeholders options:NSBackwardsSearch];
  if (first.location == NSNotFound)
    return RDLSigned(figures, negative, c);
  NSString *(^symbols)(NSString *) = ^NSString *(NSString *part) {
    part = [part stringByReplacingOccurrencesOfString:@"¤" withString:c.currencySymbol];
    part = [part stringByReplacingOccurrencesOfString:@"%" withString:c.percentSymbol];
    part = [part stringByReplacingOccurrencesOfString:@"-" withString:c.minusSign];
    return [part stringByReplacingOccurrencesOfString:@"'" withString:@""];
  };
  NSString *text = [NSString stringWithFormat:@"%@%@%@", symbols([pattern substringToIndex:first.location]), figures,
                                              symbols([pattern substringFromIndex:NSMaxRange(last)])];
  // A platform whose negative pattern is the positive one has said nothing
  // about the sign, so it goes in front.
  BOOL signs = [pattern rangeOfString:@"-"].location != NSNotFound || [pattern rangeOfString:@"("].location != NSNotFound;
  return negative && !signs ? RDLSigned(text, YES, c) : text;
}

static NSInteger RDLGeneralPrecisionOfType(RDLNumericType type) {
  switch (type) {
  case RDLNumericTypeShort:
    return kRDLShortGeneralDigits;
  case RDLNumericTypeInteger:
    return kRDLIntegerGeneralDigits;
  case RDLNumericTypeLong:
    return kRDLLongGeneralDigits;
  case RDLNumericTypeSingle:
    return kRDLSingleSignificantDigits;
  case RDLNumericTypeDecimal:
    return kRDLDecimalGeneralDigits;
  default:
    return kRDLDoubleSignificantDigits;
  }
}

// A number in one of .NET's standard formats, as .NET Framework writes it: a
// Double taken to 15 significant digits and a Single to 7 first (17 and 9 where
// the format asks for more), a whole number and a Decimal exactly; halves away
// from zero. D and X take only whole numbers and R only a Double or a Single,
// and a letter .NET does not know is refused. A Decimal in G with no precision
// is written as it is, its scale and all: 1.10D is "1.10".
static NSString *RDLStandardNumberText(RDLNumber *n, RDLNumberFormatKind kind, BOOL upper, NSInteger precision,
                                       RDLNumberCulture *c, RDLNumberFailure *failure) {
  RDLNumericType type = [n type];
  BOOL integral = [n isWhole];
  BOOL single = type == RDLNumericTypeSingle;
  BOOL floating = [n isFloatingPoint];
  if (kind == RDLNumberFormatKindUnsupported) {
    RDLFail(failure, RDLNumberFailureInvalidFormatSpecifier);
    return nil;
  }
  if (floating && !isfinite([n doubleValue]))
    return [n description];
  NSInteger significant = single ? kRDLSingleSignificantDigits : kRDLDoubleSignificantDigits;
  NSInteger roundTrip = single ? kRDLSingleRoundTripDigits : kRDLDoubleRoundTripDigits;
  switch (kind) {
  case RDLNumberFormatKindDecimal: {
    if (!integral) {
      RDLFail(failure, RDLNumberFailureInvalidFormatSpecifier);
      return nil;
    }
    RDLFormatDigits *d = RDLDigitsOfNumber(n, 0);
    NSString *whole = RDLWholeFigures(d);
    return RDLSigned([RDLZeros(precision - (NSInteger)[whole length]) stringByAppendingString:whole], d.negative, c);
  }
  case RDLNumberFormatKindHexadecimal: {
    if (!integral) {
      RDLFail(failure, RDLNumberFailureInvalidFormatSpecifier);
      return nil;
    }
    // Two's complement, in the type's own width.
    uint64_t bits = (uint64_t)[n longLongValue];
    if (type == RDLNumericTypeShort)
      bits &= UINT16_MAX;
    else if (type == RDLNumericTypeInteger)
      bits &= UINT32_MAX;
    NSString *hex = [NSString stringWithFormat:upper ? @"%llX" : @"%llx", (unsigned long long)bits];
    return [RDLZeros(precision - (NSInteger)[hex length]) stringByAppendingString:hex];
  }
  case RDLNumberFormatKindRoundTrip: {
    if (!floating) {
      RDLFail(failure, RDLNumberFailureInvalidFormatSpecifier);
      return nil;
    }
    char buffer[kRDLScientificTextCapacity];
    snprintf(buffer, sizeof buffer, "%.*e", (int)significant - 1, [n doubleValue]);
    BOOL same = single ? strtof(buffer, NULL) == [n floatValue] : strtod(buffer, NULL) == [n doubleValue];
    NSInteger digits = same ? significant : roundTrip;
    RDLFormatDigits *d = RDLDigitsOfNumber(n, digits);
    return RDLSigned(RDLGeneralFigures(d, digits, YES, c), d.negative, c);
  }
  case RDLNumberFormatKindGeneral: {
    if (type == RDLNumericTypeDecimal && precision <= 0) {
      NSString *text = [[n description] stringByReplacingOccurrencesOfString:@"." withString:c.decimalSeparator];
      return [n isNegative] ? RDLSigned([text substringFromIndex:1], YES, c) : text;
    }
    NSInteger p = precision > 0 ? precision : RDLGeneralPrecisionOfType(type);
    RDLFormatDigits *d = RDLDigitsRounded(RDLDigitsOfNumber(n, p > significant ? roundTrip : significant), p);
    return RDLSigned(RDLGeneralFigures(d, p, upper, c), d.negative, c);
  }
  case RDLNumberFormatKindExponent: {
    NSInteger decimals = precision >= 0 ? precision : kRDLDefaultExponentDecimalDigits;
    RDLFormatDigits *d = RDLDigitsRounded(RDLDigitsOfNumber(n, decimals >= significant ? roundTrip : significant), decimals + 1);
    NSInteger exponent = [d.figures length] ? d.point - 1 : 0;
    NSString *text = [RDLMantissaFigures(d, decimals, YES, c)
        stringByAppendingString:RDLExponentFigures(exponent, upper, kRDLExponentFormatDigits, c)];
    return RDLSigned(text, d.negative, c);
  }
  default: {
    NSInteger decimals = precision >= 0                               ? precision
                         : kind == RDLNumberFormatKindCurrency ? c.currencyDigits
                         : kind == RDLNumberFormatKindPercent  ? kRDLDefaultPercentDecimalDigits
                                                               : kRDLDefaultNumberDecimalDigits;
    RDLFormatDigits *d = RDLDigitsOfNumber(n, significant);
    if (kind == RDLNumberFormatKindPercent && [d.figures length])
      d.point += kRDLPercentScalePlaces;
    d = RDLDigitsRounded(d, d.point + decimals);
    NSString *figures = RDLFixedFigures(d, decimals, kind != RDLNumberFormatKindFixed, c);
    if (kind == RDLNumberFormatKindCurrency)
      return RDLInPattern(d.negative ? c.currencyNegativePattern : c.currencyPattern, figures, d.negative, c);
    if (kind == RDLNumberFormatKindPercent)
      return RDLInPattern(d.negative ? c.percentNegativePattern : c.percentPattern, figures, d.negative, c);
    return RDLSigned(figures, d.negative, c);
  }
  }
}

// The most digits an exponent in a custom format is padded to, as .NET has it.
static const NSInteger kRDLCustomExponentDigitsLimit = 10;

// Where section `section` -- 0, 1 or 2 -- of a custom number format starts, as
// .NET finds it: past quoted text and escapes, and at the first section when
// the format has not that many or the one asked for is empty.
static NSUInteger RDLFormatSection(const unichar *f, NSUInteger length, NSInteger section) {
  if (section == 0)
    return 0;
  NSUInteger src = 0;
  while (src < length) {
    unichar ch = f[src++];
    if (ch == '\'' || ch == '"') {
      while (src < length && f[src++] != ch) {
      }
    } else if (ch == '\\') {
      if (src < length)
        src += 1;
    } else if (ch == ';') {
      if (--section != 0)
        continue;
      return src < length && f[src] != ';' ? src : 0;
    }
  }
  return 0;
}

// A number in a custom format, as .NET Framework's NumberToStringFormat writes
// it: up to three sections, for positive, negative and zero, the negative one
// writing no sign of its own; 0 and # placeholders, the digits laid out from
// the decimal point, so literal text between placeholders stays where it is
// ("(###) ###-####"); a comma between placeholders groups and one just before
// the point divides by a thousand; % and ‰ scale; E+0 and the like make it
// scientific; quoted and escaped text is copied. A number that rounds to zero
// takes the zero section.
static NSString *RDLCustomNumberText(RDLNumber *n, NSString *format, RDLNumberCulture *c) {
  RDLNumericType type = [n type];
  if ([n isFloatingPoint] && !isfinite([n doubleValue]))
    return [n description];
  NSUInteger length = [format length];
  NSMutableData *buffer = [NSMutableData dataWithLength:(length + 1) * sizeof(unichar)];
  unichar *f = (unichar *)[buffer mutableBytes];
  [format getCharacters:f range:NSMakeRange(0, length)];
  RDLFormatDigits *number = RDLDigitsOfNumber(n, type == RDLNumericTypeSingle ? kRDLSingleSignificantDigits
                                                                              : kRDLDoubleSignificantDigits);
  NSUInteger section = RDLFormatSection(f, length, [number.figures length] == 0 ? 2 : number.negative ? 1 : 0);
  NSInteger digitCount, decimalPos, firstDigit, lastDigit, thousandPos, thousandCount, scaleAdjust;
  BOOL scientific, thousandSeps;
  for (;;) {
    digitCount = 0;
    decimalPos = -1;
    firstDigit = NSIntegerMax;
    lastDigit = 0;
    scientific = NO;
    thousandPos = -1;
    thousandCount = 0;
    thousandSeps = NO;
    scaleAdjust = 0;
    NSUInteger src = section;
    while (src < length) {
      unichar ch = f[src++];
      if (ch == ';')
        break;
      switch (ch) {
      case '#':
        digitCount += 1;
        break;
      case '0':
        if (firstDigit == NSIntegerMax)
          firstDigit = digitCount;
        digitCount += 1;
        lastDigit = digitCount;
        break;
      case '.':
        if (decimalPos < 0)
          decimalPos = digitCount;
        break;
      case ',':
        if (digitCount > 0 && decimalPos < 0) {
          if (thousandPos >= 0) {
            if (thousandPos == digitCount) {
              thousandCount += 1;
              break;
            }
            thousandSeps = YES;
          }
          thousandPos = digitCount;
          thousandCount = 1;
        }
        break;
      case '%':
        scaleAdjust += 2;
        break;
      case 0x2030:
        scaleAdjust += 3;
        break;
      case '\'':
      case '"':
        while (src < length && f[src++] != ch) {
        }
        break;
      case '\\':
        if (src < length)
          src += 1;
        break;
      case 'E':
      case 'e':
        if (src < length &&
            (f[src] == '0' || ((f[src] == '+' || f[src] == '-') && src + 1 < length && f[src + 1] == '0'))) {
          while (++src < length && f[src] == '0') {
          }
          scientific = YES;
        }
        break;
      default:
        break;
      }
    }
    if (decimalPos < 0)
      decimalPos = digitCount;
    if (thousandPos >= 0) {
      if (thousandPos == decimalPos)
        scaleAdjust -= thousandCount * 3;
      else
        thousandSeps = YES;
    }
    if ([number.figures length]) {
      number.point += scaleAdjust;
      number = RDLDigitsRounded(number, scientific ? digitCount : number.point + digitCount - decimalPos);
      if ([number.figures length] == 0) {
        NSUInteger zero = RDLFormatSection(f, length, 2);
        if (zero != section) {
          section = zero;
          continue;
        }
      }
    } else {
      number.negative = NO;
      number.point = 0;
    }
    break;
  }
  NSString *figures = number.figures;
  firstDigit = firstDigit < decimalPos ? decimalPos - firstDigit : 0;
  lastDigit = lastDigit > decimalPos ? decimalPos - lastDigit : 0;
  NSInteger digPos = scientific ? decimalPos : MAX(number.point, decimalPos);
  NSInteger adjust = scientific ? 0 : number.point - decimalPos;
  // Where group separators go, counted in digits from the decimal point.
  NSMutableArray<NSNumber *> *separators = [NSMutableArray array];
  if (thousandSeps && [c.groupSeparator length]) {
    NSInteger size = c.groupSize, total = c.groupSize;
    NSInteger digits = MAX(firstDigit, digPos + (adjust < 0 ? adjust : 0));
    while (size > 0 && digits > total) {
      [separators addObject:@(total)];
      if (c.secondaryGroupSize > 0)
        size = c.secondaryGroupSize;
      total += size;
    }
  }
  NSInteger separator = (NSInteger)[separators count] - 1;
  NSUInteger next = 0;
  NSMutableString *out = [NSMutableString string];
  if (number.negative && section == 0)
    [out appendString:c.minusSign];
  BOOL decimalWritten = NO;
  NSUInteger src = section;
  while (src < length) {
    unichar ch = f[src++];
    if (ch == ';')
      break;
    if (adjust > 0 && (ch == '#' || ch == '0' || ch == '.')) {
      // More whole digits than placeholders: the rest go before the first.
      while (adjust > 0) {
        unichar digit = next < [figures length] ? [figures characterAtIndex:next++] : '0';
        [out appendFormat:@"%C", digit];
        if (thousandSeps && digPos > 1 && separator >= 0 && digPos == [separators[(NSUInteger)separator] integerValue] + 1) {
          [out appendString:c.groupSeparator];
          separator -= 1;
        }
        digPos -= 1;
        adjust -= 1;
      }
    }
    switch (ch) {
    case '#':
    case '0': {
      unichar digit = 0;
      if (adjust < 0) {
        adjust += 1;
        digit = digPos <= firstDigit ? '0' : 0;
      } else {
        digit = next < [figures length] ? [figures characterAtIndex:next++] : (digPos > lastDigit ? '0' : 0);
      }
      if (digit) {
        [out appendFormat:@"%C", digit];
        if (thousandSeps && digPos > 1 && separator >= 0 && digPos == [separators[(NSUInteger)separator] integerValue] + 1) {
          [out appendString:c.groupSeparator];
          separator -= 1;
        }
      }
      digPos -= 1;
      break;
    }
    case '.':
      if (digPos != 0 || decimalWritten)
        break;
      if (lastDigit < 0 || (decimalPos < digitCount && next < [figures length])) {
        [out appendString:c.decimalSeparator];
        decimalWritten = YES;
      }
      break;
    case 0x2030:
      [out appendString:c.perMilleSymbol];
      break;
    case '%':
      [out appendString:c.percentSymbol];
      break;
    case ',':
      break;
    case '\'':
    case '"':
      while (src < length) {
        unichar quoted = f[src++];
        if (quoted == ch)
          break;
        [out appendFormat:@"%C", quoted];
      }
      break;
    case '\\':
      if (src < length)
        [out appendFormat:@"%C", f[src++]];
      break;
    case 'E':
    case 'e': {
      if (!scientific) {
        [out appendFormat:@"%C", ch];
        if (src < length && (f[src] == '+' || f[src] == '-'))
          [out appendFormat:@"%C", f[src++]];
        while (src < length && f[src] == '0')
          [out appendFormat:@"%C", f[src++]];
        break;
      }
      BOOL positiveSign = NO;
      NSInteger zeros = 0;
      if (src < length && f[src] == '0') {
        zeros += 1;
      } else if (src + 1 < length && f[src] == '+' && f[src + 1] == '0') {
        positiveSign = YES;
      } else if (!(src + 1 < length && f[src] == '-' && f[src + 1] == '0')) {
        [out appendFormat:@"%C", ch];
        break;
      }
      while (++src < length && f[src] == '0')
        zeros += 1;
      zeros = MIN(zeros, kRDLCustomExponentDigitsLimit);
      NSInteger exponent = [figures length] ? number.point - decimalPos : 0;
      NSString *digits = [NSString stringWithFormat:@"%ld", labs((long)exponent)];
      [out appendFormat:@"%C%@%@%@", ch, exponent < 0 ? c.minusSign : positiveSign ? c.plusSign : @"",
                        RDLZeros(zeros - (NSInteger)[digits length]), digits];
      scientific = NO;
      break;
    }
    default:
      [out appendFormat:@"%C", ch];
      break;
    }
  }
  return out;
}

#pragma mark - RDLNumber

// The arithmetic operators, for the one method that does them all.
typedef NS_ENUM(NSInteger, RDLArithmetic) {
  RDLArithmeticUnspecified = 0,
  RDLArithmeticAdd,
  RDLArithmeticSubtract,
  RDLArithmeticMultiply,
  RDLArithmeticDivide,
  RDLArithmeticIntegerDivide,
  RDLArithmeticModulo,
};

typedef NS_ENUM(NSInteger, RDLBitwise) {
  RDLBitwiseUnspecified = 0,
  RDLBitwiseAnd,
  RDLBitwiseOr,
  RDLBitwiseXor,
  RDLBitwiseNot,
};

static BOOL RDLIsWholeType(RDLNumericType type) {
  return type == RDLNumericTypeShort || type == RDLNumericTypeInteger || type == RDLNumericTypeLong;
}

@implementation RDLNumber {
  RDLNumericType _type;
  int64_t _whole;       // Short, Integer, Long
  double _floating;     // Single, Double
  RDLDecimal _decimal;  // Decimal
}

#pragma mark Making one

+ (instancetype)numberWithType:(RDLNumericType)type {
  RDLNumber *n = [[self alloc] init];
  n->_type = type;
  return n;
}

+ (instancetype)numberWithShort:(int16_t)value {
  RDLNumber *n = [self numberWithType:RDLNumericTypeShort];
  n->_whole = value;
  return n;
}

+ (instancetype)numberWithInteger:(int32_t)value {
  RDLNumber *n = [self numberWithType:RDLNumericTypeInteger];
  n->_whole = value;
  return n;
}

+ (instancetype)numberWithLong:(int64_t)value {
  RDLNumber *n = [self numberWithType:RDLNumericTypeLong];
  n->_whole = value;
  return n;
}

+ (instancetype)numberWithSingle:(float)value {
  RDLNumber *n = [self numberWithType:RDLNumericTypeSingle];
  n->_floating = value;
  return n;
}

+ (instancetype)numberWithDouble:(double)value {
  RDLNumber *n = [self numberWithType:RDLNumericTypeDouble];
  n->_floating = value;
  return n;
}

+ (instancetype)numberWithDecimal:(RDLDecimal)value {
  RDLNumber *n = [self numberWithType:RDLNumericTypeDecimal];
  n->_decimal = value;
  return n;
}

+ (instancetype)decimalWithLong:(int64_t)value {
  return [self numberWithDecimal:RDLDecimalWithLong(value)];
}

+ (instancetype)decimalWithUnsignedLong:(uint64_t)value {
  return [self numberWithDecimal:RDLDecimalWithMagnitude(value, NO)];
}

+ (instancetype)numberWithWhole:(int64_t)value type:(RDLNumericType)type {
  switch (type) {
  case RDLNumericTypeShort:
    return value < INT16_MIN || value > INT16_MAX ? nil : [self numberWithShort:(int16_t)value];
  case RDLNumericTypeInteger:
    return value < INT32_MIN || value > INT32_MAX ? nil : [self numberWithInteger:(int32_t)value];
  case RDLNumericTypeLong:
    return [self numberWithLong:value];
  case RDLNumericTypeDecimal:
    return [self decimalWithLong:value];
  default:
    return nil;
  }
}

+ (instancetype)decimalWithText:(NSString *)text {
  RDLDecimal d;
  if (text == nil || RDLDecimalFromText(text, &d) != RDLDecimalParseNumber)
    return nil;
  return [self numberWithDecimal:d];
}

+ (instancetype)doubleWithText:(NSString *)text {
  NSString *s = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([s length] == 0)
    return nil;
  s = [[s stringByReplacingOccurrencesOfString:@"," withString:@""] stringByReplacingOccurrencesOfString:@"$"
                                                                                             withString:@""];
  NSScanner *scanner = [NSScanner scannerWithString:s];
  double d = 0;
  if (![scanner scanDouble:&d] || ![scanner isAtEnd])
    return nil;
  return [self numberWithDouble:d];
}

+ (instancetype)numberWithFoundationNumber:(NSNumber *)number {
  if (![number isKindOfClass:[NSNumber class]] || RDLNumberIsBoolean(number))
    return nil;
  if ([number isKindOfClass:[NSDecimalNumber class]])
    return [self decimalWithText:[number description]];
  const char *encoding = [number objCType];
  switch (encoding ? encoding[0] : 'd') {
  case 'c':
  case 'C':
  case 's':
    return [self numberWithShort:[number shortValue]];
  case 'S':
  case 'i':
    return [self numberWithInteger:[number intValue]];
  case 'I':
  case 'l':
  case 'L':
  case 'q':
    return [self numberWithLong:[number longLongValue]];
  case 'Q':
    return [number unsignedLongLongValue] > INT64_MAX ? [self decimalWithUnsignedLong:[number unsignedLongLongValue]]
                                                      : [self numberWithLong:[number longLongValue]];
  case 'f':
    return [self numberWithSingle:[number floatValue]];
  default:
    return [self numberWithDouble:[number doubleValue]];
  }
}

+ (instancetype)numberFromValue:(id)value {
  if ([value isKindOfClass:[RDLNumber class]])
    return value;
  return [value isKindOfClass:[NSNumber class]] ? [self numberWithFoundationNumber:value] : nil;
}

- (id)copyWithZone:(NSZone *)zone {
  return self;
}

#pragma mark What it is

- (RDLNumericType)type {
  return _type;
}

- (BOOL)isWhole {
  return RDLIsWholeType(_type);
}

- (BOOL)isFloatingPoint {
  return _type == RDLNumericTypeSingle || _type == RDLNumericTypeDouble;
}

- (BOOL)isNaN {
  return [self isFloatingPoint] && isnan(_floating);
}

- (BOOL)isZero {
  if ([self isWhole])
    return _whole == 0;
  if (_type == RDLNumericTypeDecimal)
    return _decimal.mantissa == 0;
  return _floating == 0;
}

- (BOOL)isNegative {
  if ([self isWhole])
    return _whole < 0;
  if (_type == RDLNumericTypeDecimal)
    return _decimal.negative && _decimal.mantissa != 0;
  return _floating < 0;
}

- (double)doubleValue {
  if ([self isWhole])
    return (double)_whole;
  if (_type == RDLNumericTypeDecimal)
    return RDLDecimalDouble(_decimal);
  return _floating;
}

- (float)floatValue {
  return (float)[self doubleValue];
}

- (long long)longLongValue {
  if ([self isWhole])
    return _whole;
  if (_type == RDLNumericTypeDecimal) {
    RDLDecimal whole = RDLDecimalRounded(_decimal, 0, RDLDropRoundingTowardZero);
    if (whole.mantissa > (RDLUInt128)INT64_MAX)
      return whole.negative ? INT64_MIN : INT64_MAX;
    return whole.negative ? -(int64_t)whole.mantissa : (int64_t)whole.mantissa;
  }
  double d = trunc(_floating);
  if (isnan(d))
    return 0;
  if (d >= (double)INT64_MAX)
    return INT64_MAX;
  return d <= (double)INT64_MIN ? INT64_MIN : (int64_t)d;
}

- (NSInteger)integerValue {
  long long whole = [self longLongValue];
  return whole > NSIntegerMax ? NSIntegerMax : whole < NSIntegerMin ? NSIntegerMin : (NSInteger)whole;
}

- (NSUInteger)scale {
  return _type == RDLNumericTypeDecimal ? _decimal.scale : 0;
}

- (NSNumber *)foundationNumber {
  switch (_type) {
  case RDLNumericTypeShort:
    return [NSNumber numberWithShort:(short)_whole];
  case RDLNumericTypeInteger:
    return [NSNumber numberWithInt:(int)_whole];
  case RDLNumericTypeLong:
    return [NSNumber numberWithLongLong:_whole];
  case RDLNumericTypeSingle:
    return [NSNumber numberWithFloat:(float)_floating];
  case RDLNumericTypeDecimal:
    return [NSDecimalNumber decimalNumberWithString:RDLDecimalText(_decimal)
                                             locale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
  default:
    return [NSNumber numberWithDouble:_floating];
  }
}

// The value as a Decimal, for a whole number or a Decimal.
- (RDLDecimal)exactDecimal {
  return _type == RDLNumericTypeDecimal ? _decimal : RDLDecimalWithLong(_whole);
}

// A number as \ and the bitwise operators take one: a whole number as it is,
// anything else rounded to even into a Long.
- (RDLNumber *)wholeOperandWithFailure:(RDLNumberFailure *)failure {
  if ([self isWhole])
    return self;
  if (_type == RDLNumericTypeDecimal) {
    RDLDecimal whole = RDLDecimalRounded(_decimal, 0, RDLDropRoundingToEven);
    RDLUInt128 largest = whole.negative ? (RDLUInt128)INT64_MAX + 1 : (RDLUInt128)INT64_MAX;
    if (whole.mantissa > largest) {
      RDLFail(failure, RDLNumberFailureOverflow);
      return nil;
    }
    int64_t value = whole.negative ? (int64_t)(0 - (uint64_t)whole.mantissa) : (int64_t)whole.mantissa;
    return [RDLNumber numberWithLong:value];
  }
  double d = rint(_floating);
  // One past the largest Long is the power of two it rounds to as a Double.
  if (!(d >= (double)INT64_MIN && d < -(double)INT64_MIN)) {
    RDLFail(failure, RDLNumberFailureOverflow);
    return nil;
  }
  return [RDLNumber numberWithLong:(int64_t)d];
}

#pragma mark VB's operators

- (RDLNumber *)arithmetic:(RDLArithmetic)operation with:(RDLNumber *)other failure:(RDLNumberFailure *)failure {
  RDLNumber *a = self, *b = other;
  if (operation == RDLArithmeticIntegerDivide) {
    a = [a wholeOperandWithFailure:failure];
    b = a ? [b wholeOperandWithFailure:failure] : nil;
    if (a == nil || b == nil)
      return nil;
  }
  RDLNumericType type = MAX(a->_type, b->_type);
  if (operation == RDLArithmeticDivide && RDLIsWholeType(type))
    type = RDLNumericTypeDouble;
  if (RDLIsWholeType(type)) {
    int64_t x = a->_whole, y = b->_whole, r = 0;
    BOOL overflow = NO;
    switch (operation) {
    case RDLArithmeticAdd:
      overflow = __builtin_add_overflow(x, y, &r);
      break;
    case RDLArithmeticSubtract:
      overflow = __builtin_sub_overflow(x, y, &r);
      break;
    case RDLArithmeticMultiply:
      overflow = __builtin_mul_overflow(x, y, &r);
      break;
    case RDLArithmeticIntegerDivide:
      if (y == 0) {
        RDLFail(failure, RDLNumberFailureDivisionByZero);
        return nil;
      }
      overflow = x == INT64_MIN && y == -1;
      r = overflow ? 0 : x / y;
      break;
    case RDLArithmeticModulo:
      if (y == 0) {
        RDLFail(failure, RDLNumberFailureDivisionByZero);
        return nil;
      }
      r = y == -1 ? 0 : x % y;
      break;
    default:
      return nil;
    }
    RDLNumber *result = overflow ? nil : [RDLNumber numberWithWhole:r type:type];
    if (result == nil)
      RDLFail(failure, RDLNumberFailureOverflow);
    return result;
  }
  if (type == RDLNumericTypeDecimal) {
    RDLDecimal x = [a exactDecimal], y = [b exactDecimal], r;
    RDLNumberFailure why = RDLNumberFailureUnspecified;
    switch (operation) {
    case RDLArithmeticAdd:
      why = RDLDecimalAdd(x, y, &r) ? RDLNumberFailureUnspecified : RDLNumberFailureOverflow;
      break;
    case RDLArithmeticSubtract:
      y.negative = !y.negative && y.mantissa != 0;
      why = RDLDecimalAdd(x, y, &r) ? RDLNumberFailureUnspecified : RDLNumberFailureOverflow;
      break;
    case RDLArithmeticMultiply:
      why = RDLDecimalMultiply(x, y, &r) ? RDLNumberFailureUnspecified : RDLNumberFailureOverflow;
      break;
    case RDLArithmeticDivide:
      why = RDLDecimalDivide(x, y, &r);
      break;
    case RDLArithmeticModulo:
      why = RDLDecimalModulo(x, y, &r);
      break;
    default:
      return nil;
    }
    if (why != RDLNumberFailureUnspecified) {
      RDLFail(failure, why);
      return nil;
    }
    return [RDLNumber numberWithDecimal:r];
  }
  double x = [a doubleValue], y = [b doubleValue], r = 0;
  switch (operation) {
  case RDLArithmeticAdd:
    r = x + y;
    break;
  case RDLArithmeticSubtract:
    r = x - y;
    break;
  case RDLArithmeticMultiply:
    r = x * y;
    break;
  case RDLArithmeticDivide:
    r = x / y;
    break;
  case RDLArithmeticModulo:
    r = fmod(x, y);
    break;
  default:
    return nil;
  }
  return type == RDLNumericTypeSingle ? [RDLNumber numberWithSingle:(float)r] : [RDLNumber numberWithDouble:r];
}

- (RDLNumber *)numberByAdding:(RDLNumber *)other failure:(RDLNumberFailure *)failure {
  return [self arithmetic:RDLArithmeticAdd with:other failure:failure];
}

- (RDLNumber *)numberBySubtracting:(RDLNumber *)other failure:(RDLNumberFailure *)failure {
  return [self arithmetic:RDLArithmeticSubtract with:other failure:failure];
}

- (RDLNumber *)numberByMultiplyingBy:(RDLNumber *)other failure:(RDLNumberFailure *)failure {
  return [self arithmetic:RDLArithmeticMultiply with:other failure:failure];
}

- (RDLNumber *)numberByDividingBy:(RDLNumber *)other failure:(RDLNumberFailure *)failure {
  return [self arithmetic:RDLArithmeticDivide with:other failure:failure];
}

- (RDLNumber *)numberByIntegerDividingBy:(RDLNumber *)other failure:(RDLNumberFailure *)failure {
  return [self arithmetic:RDLArithmeticIntegerDivide with:other failure:failure];
}

- (RDLNumber *)numberByModulo:(RDLNumber *)other failure:(RDLNumberFailure *)failure {
  return [self arithmetic:RDLArithmeticModulo with:other failure:failure];
}

- (RDLNumber *)numberByRaisingToPower:(RDLNumber *)other {
  return [RDLNumber numberWithDouble:pow([self doubleValue], [other doubleValue])];
}

- (RDLNumber *)negatedWithFailure:(RDLNumberFailure *)failure {
  if ([self isWhole]) {
    RDLNumber *r = _whole == INT64_MIN ? nil : [RDLNumber numberWithWhole:-_whole type:_type];
    if (r == nil)
      RDLFail(failure, RDLNumberFailureOverflow);
    return r;
  }
  if (_type == RDLNumericTypeDecimal) {
    RDLDecimal d = _decimal;
    d.negative = !d.negative && d.mantissa != 0;
    return [RDLNumber numberWithDecimal:d];
  }
  return _type == RDLNumericTypeSingle ? [RDLNumber numberWithSingle:-(float)_floating]
                                       : [RDLNumber numberWithDouble:-_floating];
}

- (RDLNumber *)absoluteValueWithFailure:(RDLNumberFailure *)failure {
  if ([self isWhole])
    return _whole < 0 ? [self negatedWithFailure:failure] : self;
  if (_type == RDLNumericTypeDecimal) {
    RDLDecimal d = _decimal;
    d.negative = NO;
    return [RDLNumber numberWithDecimal:d];
  }
  return _type == RDLNumericTypeSingle ? [RDLNumber numberWithSingle:fabsf((float)_floating)]
                                       : [RDLNumber numberWithDouble:fabs(_floating)];
}

- (RDLNumber *)bitwise:(RDLBitwise)operation with:(RDLNumber *)other failure:(RDLNumberFailure *)failure {
  RDLNumber *a = [self wholeOperandWithFailure:failure];
  RDLNumber *b = operation == RDLBitwiseNot ? a : [other wholeOperandWithFailure:failure];
  if (a == nil || b == nil)
    return nil;
  int64_t x = a->_whole, y = b->_whole;
  int64_t r = operation == RDLBitwiseNot ? ~x : operation == RDLBitwiseAnd ? (x & y) : operation == RDLBitwiseOr ? (x | y) : (x ^ y);
  RDLNumericType type = operation == RDLBitwiseNot ? a->_type : MAX(a->_type, b->_type);
  RDLNumber *result = [RDLNumber numberWithWhole:r type:type];
  if (result == nil)
    RDLFail(failure, RDLNumberFailureOverflow);
  return result;
}

- (RDLNumber *)numberByAnd:(RDLNumber *)other failure:(RDLNumberFailure *)failure {
  return [self bitwise:RDLBitwiseAnd with:other failure:failure];
}

- (RDLNumber *)numberByOr:(RDLNumber *)other failure:(RDLNumberFailure *)failure {
  return [self bitwise:RDLBitwiseOr with:other failure:failure];
}

- (RDLNumber *)numberByXor:(RDLNumber *)other failure:(RDLNumberFailure *)failure {
  return [self bitwise:RDLBitwiseXor with:other failure:failure];
}

- (RDLNumber *)bitwiseNotWithFailure:(RDLNumberFailure *)failure {
  return [self bitwise:RDLBitwiseNot with:nil failure:failure];
}

#pragma mark Comparing

- (BOOL)getComparison:(NSComparisonResult *)result withNumber:(RDLNumber *)other {
  RDLNumericType type = MAX(_type, other->_type);
  NSComparisonResult c = NSOrderedSame;
  if (RDLIsWholeType(type)) {
    c = _whole < other->_whole ? NSOrderedAscending : _whole > other->_whole ? NSOrderedDescending : NSOrderedSame;
  } else if (type == RDLNumericTypeDecimal) {
    c = RDLDecimalCompare([self exactDecimal], [other exactDecimal]);
  } else {
    double x = [self doubleValue], y = [other doubleValue];
    if (isnan(x) || isnan(y))
      return NO;
    c = x < y ? NSOrderedAscending : x > y ? NSOrderedDescending : NSOrderedSame;
  }
  if (result)
    *result = c;
  return YES;
}

- (NSComparisonResult)compare:(RDLNumber *)other {
  NSComparisonResult c = NSOrderedSame;
  if ([self getComparison:&c withNumber:other])
    return c;
  BOOL mine = [self isNaN], theirs = [other isNaN];
  return mine && theirs ? NSOrderedSame : mine ? NSOrderedAscending : NSOrderedDescending;
}

- (BOOL)isEqualToNumber:(RDLNumber *)other {
  NSComparisonResult c = NSOrderedAscending;
  return other != nil && [self getComparison:&c withNumber:other] && c == NSOrderedSame;
}

- (BOOL)isEqual:(id)object {
  return object == self || ([object isKindOfClass:[RDLNumber class]] && [self isEqualToNumber:object]);
}

// Equal numbers of any type hash alike: a whole value by itself, anything
// else by its Double, the nearest any of them can say.
- (NSUInteger)hash {
  if ([self isWhole])
    return (NSUInteger)_whole;
  double d = [self doubleValue];
  if (d == 0)
    return 0;
  if (d == trunc(d) && d >= (double)INT64_MIN && d < -(double)INT64_MIN)
    return (NSUInteger)(int64_t)d;
  uint64_t bits = 0;
  memcpy(&bits, &d, sizeof bits);
  return (NSUInteger)(bits ^ (bits >> (kRDLLimbBits / 2)));
}

#pragma mark Converting

// A whole-number target's range and the type its result is carried in.
static void RDLWholeTargetRange(RDLConversionTarget target, int64_t *minimum, uint64_t *maximum,
                                RDLNumericType *carried) {
  switch (target) {
  case RDLConversionTargetByte:
    *minimum = 0, *maximum = UINT8_MAX, *carried = RDLNumericTypeShort;
    return;
  case RDLConversionTargetSByte:
    *minimum = INT8_MIN, *maximum = INT8_MAX, *carried = RDLNumericTypeShort;
    return;
  case RDLConversionTargetShort:
    *minimum = INT16_MIN, *maximum = INT16_MAX, *carried = RDLNumericTypeShort;
    return;
  case RDLConversionTargetUShort:
    *minimum = 0, *maximum = UINT16_MAX, *carried = RDLNumericTypeInteger;
    return;
  case RDLConversionTargetInteger:
    *minimum = INT32_MIN, *maximum = INT32_MAX, *carried = RDLNumericTypeInteger;
    return;
  case RDLConversionTargetUInteger:
    *minimum = 0, *maximum = UINT32_MAX, *carried = RDLNumericTypeLong;
    return;
  case RDLConversionTargetULong:
    *minimum = 0, *maximum = UINT64_MAX, *carried = RDLNumericTypeDecimal;
    return;
  default:
    *minimum = INT64_MIN, *maximum = INT64_MAX, *carried = RDLNumericTypeLong;
    return;
  }
}

- (RDLNumber *)numberConvertedTo:(RDLConversionTarget)target failure:(RDLNumberFailure *)failure {
  switch (target) {
  case RDLConversionTargetSingle:
    return [RDLNumber numberWithSingle:[self floatValue]];
  case RDLConversionTargetDouble:
    return [RDLNumber numberWithDouble:[self doubleValue]];
  case RDLConversionTargetDecimal: {
    if (_type == RDLNumericTypeDecimal || [self isWhole])
      return [RDLNumber numberWithDecimal:[self exactDecimal]];
    RDLDecimal d;
    RDLNumberFailure why = RDLDecimalFromDouble(_floating, _type == RDLNumericTypeSingle, &d);
    if (why != RDLNumberFailureUnspecified) {
      RDLFail(failure, why);
      return nil;
    }
    return [RDLNumber numberWithDecimal:d];
  }
  default:
    break;
  }
  int64_t minimum = 0;
  uint64_t maximum = 0;
  RDLNumericType carried = RDLNumericTypeUnspecified;
  RDLWholeTargetRange(target, &minimum, &maximum, &carried);
  RDLNumber *result = nil;
  if ([self isWhole]) {
    if (!(_whole < minimum || (_whole > 0 && (uint64_t)_whole > maximum)))
      result = carried == RDLNumericTypeDecimal ? [RDLNumber decimalWithLong:_whole]
                                                : [RDLNumber numberWithWhole:_whole type:carried];
  } else if (_type == RDLNumericTypeDecimal) {
    RDLDecimal whole = RDLDecimalRounded(_decimal, 0, RDLDropRoundingToEven);
    RDLUInt128 lowest = minimum < 0 ? (RDLUInt128)(-(minimum + 1)) + 1 : 0;
    BOOL fits = whole.negative ? whole.mantissa <= lowest : whole.mantissa <= (RDLUInt128)maximum;
    if (fits && carried == RDLNumericTypeDecimal)
      result = [RDLNumber numberWithDecimal:whole];
    else if (fits)
      result = [RDLNumber numberWithWhole:whole.negative ? (int64_t)(0 - (uint64_t)whole.mantissa)
                                                        : (int64_t)whole.mantissa
                                     type:carried];
  } else {
    double d = rint(_floating);
    // Every bound but the largest Long and ULong is exact as a Double, and one
    // past those is the power of two they round to.
    if (!(isnan(d) || d < (double)minimum || d >= (double)maximum + 1.0))
      result = carried == RDLNumericTypeDecimal ? [RDLNumber decimalWithUnsignedLong:(uint64_t)d]
                                                : [RDLNumber numberWithWhole:(int64_t)d type:carried];
  }
  if (result == nil)
    RDLFail(failure, RDLNumberFailureOverflow);
  return result;
}

+ (RDLNumber *)largestValueOfConversionTarget:(RDLConversionTarget)target {
  int64_t minimum = 0;
  uint64_t maximum = 0;
  RDLNumericType carried = RDLNumericTypeUnspecified;
  RDLWholeTargetRange(target, &minimum, &maximum, &carried);
  return [RDLNumber decimalWithUnsignedLong:maximum];
}

#pragma mark Maths

static double RDLDoubleWhole(double d, RDLWholeRounding rounding) {
  if (rounding == RDLWholeRoundingCeiling)
    return ceil(d);
  return rounding == RDLWholeRoundingTruncate ? trunc(d) : floor(d);
}

- (RDLNumber *)wholePartTowardZero:(BOOL)towardZero {
  if ([self isWhole])
    return self;
  RDLWholeRounding rounding = towardZero ? RDLWholeRoundingTruncate : RDLWholeRoundingFloor;
  if (_type == RDLNumericTypeDecimal)
    return [RDLNumber numberWithDecimal:RDLDecimalWhole(_decimal, rounding)];
  double d = RDLDoubleWhole(_floating, rounding);
  return _type == RDLNumericTypeSingle ? [RDLNumber numberWithSingle:(float)d] : [RDLNumber numberWithDouble:d];
}

- (RDLNumber *)numberByRounding:(RDLWholeRounding)rounding {
  if (_type == RDLNumericTypeDecimal || [self isWhole])
    return [RDLNumber numberWithDecimal:RDLDecimalWhole([self exactDecimal], rounding)];
  return [RDLNumber numberWithDouble:RDLDoubleWhole(_floating, rounding)];
}

- (RDLNumber *)numberRoundedToDigits:(NSInteger)digits
                            midpoint:(RDLMidpointRounding)midpoint
                             failure:(RDLNumberFailure *)failure {
  BOOL away = midpoint == RDLMidpointRoundingAwayFromZero;
  if (_type == RDLNumericTypeDecimal || [self isWhole]) {
    if (digits < 0 || digits > kRDLDecimalRoundingDigitsLimit) {
      RDLFail(failure, RDLNumberFailureDecimalRoundingDigits);
      return nil;
    }
    RDLDecimal d = RDLDecimalRounded([self exactDecimal], (unsigned)digits,
                                     away ? RDLDropRoundingAwayFromZero : RDLDropRoundingToEven);
    return [RDLNumber numberWithDecimal:d];
  }
  if (digits < 0 || digits > kRDLDoubleRoundingDigitsLimit) {
    RDLFail(failure, RDLNumberFailureDoubleRoundingDigits);
    return nil;
  }
  double d = _floating;
  if (fabs(d) < kRDLDoubleRoundingMagnitudeLimit) {
    double power = pow((double)kRDLTen, (double)digits);
    // rint follows the rounding mode, which is to even unless changed; round
    // takes a half away from zero.
    d = (away ? round(d * power) : rint(d * power)) / power;
  }
  return [RDLNumber numberWithDouble:d];
}

- (RDLNumber *)signWithFailure:(RDLNumberFailure *)failure {
  if ([self isNaN]) {
    RDLFail(failure, RDLNumberFailureNotANumber);
    return nil;
  }
  return [RDLNumber numberWithInteger:[self isZero] ? 0 : [self isNegative] ? -1 : 1];
}

+ (RDLNumber *)extremeOf:(RDLNumber *)first and:(RDLNumber *)second largest:(BOOL)largest {
  RDLNumericType type = MAX(first->_type, second->_type);
  if (type == RDLNumericTypeDecimal || RDLIsWholeType(type)) {
    NSComparisonResult c = NSOrderedSame;
    [first getComparison:&c withNumber:second];
    RDLNumber *picked = (c == NSOrderedDescending) == largest ? first : second;
    return type == RDLNumericTypeDecimal ? [RDLNumber numberWithDecimal:[picked exactDecimal]]
                                         : [RDLNumber numberWithWhole:picked->_whole type:type];
  }
  double x = [first doubleValue], y = [second doubleValue];
  double r = isnan(x) || isnan(y) ? NAN : largest ? MAX(x, y) : MIN(x, y);
  return type == RDLNumericTypeSingle ? [RDLNumber numberWithSingle:(float)r] : [RDLNumber numberWithDouble:r];
}

#pragma mark Writing

- (NSString *)description {
  switch (_type) {
  case RDLNumericTypeShort:
  case RDLNumericTypeInteger:
  case RDLNumericTypeLong:
    return [NSString stringWithFormat:@"%lld", (long long)_whole];
  case RDLNumericTypeDecimal:
    return RDLDecimalText(_decimal);
  case RDLNumericTypeSingle:
    return RDLGeneralNumberText(_floating, kRDLSingleSignificantDigits);
  default:
    return RDLGeneralNumberText(_floating, kRDLDoubleSignificantDigits);
  }
}


- (NSString *)textWithFormat:(NSString *)format
                     culture:(RDLNumberCulture *)culture
                     failure:(RDLNumberFailure *)failure {
  BOOL upper = NO;
  NSInteger precision = -1;
  RDLNumberFormatKind standard = RDLStandardNumberFormat(format, &upper, &precision);
  if (standard != RDLNumberFormatKindUnspecified)
    return RDLStandardNumberText(self, standard, upper, precision, culture, failure);
  return RDLCustomNumberText(self, format, culture);
}

- (NSString *)visualBasicTextInStyle:(RDLVisualBasicNumberStyle)style
                            decimals:(NSInteger)decimals
                         leadingZero:(RDLVisualBasicTriState)leadingZero
                         parentheses:(RDLVisualBasicTriState)parentheses
                            grouping:(RDLVisualBasicTriState)grouping
                             culture:(RDLNumberCulture *)culture {
  RDLNumberCulture *c = [culture copy];
  if (decimals == kRDLCultureDigits)
    decimals = style == RDLVisualBasicNumberStyleCurrency  ? c.currencyDigits
               : style == RDLVisualBasicNumberStylePercent ? kRDLDefaultPercentDecimalDigits
                                                           : kRDLDefaultNumberDecimalDigits;
  if (grouping == RDLVisualBasicTriStateFalse)
    c.groupSize = 0;
  if ([self isFloatingPoint] && !isfinite([self doubleValue]))
    return [self description];
  RDLFormatDigits *d = RDLDigitsOfNumber(self, [self type] == RDLNumericTypeSingle ? kRDLSingleSignificantDigits
                                                                                    : kRDLDoubleSignificantDigits);
  if (style == RDLVisualBasicNumberStylePercent && [d.figures length])
    d.point += kRDLPercentScalePlaces;
  d = RDLDigitsRounded(d, d.point + decimals);
  NSString *figures = RDLFixedFigures(d, decimals, YES, c);
  // Without its leading digit a fraction starts at its point: ".50".
  NSString *zeroPoint = [@"0" stringByAppendingString:c.decimalSeparator];
  if (leadingZero == RDLVisualBasicTriStateFalse && d.point <= 0 && [figures hasPrefix:zeroPoint])
    figures = [figures substringFromIndex:1];
  if (style == RDLVisualBasicNumberStyleNumber) {
    if (d.negative && parentheses == RDLVisualBasicTriStateTrue)
      return [NSString stringWithFormat:@"(%@)", figures];
    return RDLSigned(figures, d.negative, c);
  }
  NSString *positive = style == RDLVisualBasicNumberStyleCurrency ? c.currencyPattern : c.percentPattern;
  NSString *negative = style == RDLVisualBasicNumberStyleCurrency ? c.currencyNegativePattern : c.percentNegativePattern;
  if (parentheses == RDLVisualBasicTriStateTrue)
    negative = [NSString stringWithFormat:@"(%@)", positive];
  else if (parentheses == RDLVisualBasicTriStateFalse)
    negative = [@"-" stringByAppendingString:positive];
  return RDLInPattern(d.negative ? negative : positive, figures, d.negative, c);
}

@end

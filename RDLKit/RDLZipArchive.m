#import "RDLZipArchive.h"
#import <zlib.h>

// Signatures and the field offsets they introduce, from the PKWARE
// specification. Named rather than spelled inline, because an off-by-two in a
// magic number reads as a corrupt file rather than as a bug.
static const uint32_t kRDLEndOfCentralDirectorySig = 0x06054b50;
static const uint32_t kRDLCentralFileHeaderSig = 0x02014b50;
static const uint32_t kRDLLocalFileHeaderSig = 0x04034b50;

static const NSUInteger kRDLEOCDMinimumLength = 22;
// A ZIP comment can be 64 KB, and the end record sits before it.
static const NSUInteger kRDLMaxCommentLength = 0xFFFF;

@interface RDLZipEntry : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) uint16_t method;
@property (nonatomic, assign) uint32_t compressedSize;
@property (nonatomic, assign) uint32_t uncompressedSize;
@property (nonatomic, assign) uint32_t localHeaderOffset;
@end
@implementation RDLZipEntry
@end

@implementation RDLZipArchive {
  NSData *_data;
  NSMutableArray<NSString *> *_names;
  NSMutableDictionary<NSString *, RDLZipEntry *> *_entries;
}

#pragma mark - Reading little-endian fields safely

// Every read is bounds-checked against the archive: a truncated or hostile
// file must fail, not walk off the end of the buffer.
static BOOL RDLReadU16(NSData *data, NSUInteger at, uint16_t *out) {
  if (at + 2 > [data length])
    return NO;
  const uint8_t *b = (const uint8_t *)[data bytes] + at;
  *out = (uint16_t)(b[0] | (b[1] << 8));
  return YES;
}

static BOOL RDLReadU32(NSData *data, NSUInteger at, uint32_t *out) {
  if (at + 4 > [data length])
    return NO;
  const uint8_t *b = (const uint8_t *)[data bytes] + at;
  *out = (uint32_t)b[0] | ((uint32_t)b[1] << 8) | ((uint32_t)b[2] << 16) | ((uint32_t)b[3] << 24);
  return YES;
}

static NSError *RDLZipError(NSString *why) {
  return [NSError errorWithDomain:@"RDLKit"
                             code:10
                         userInfo:@{NSLocalizedDescriptionKey : why}];
}

#pragma mark - Opening

+ (instancetype)archiveWithData:(NSData *)data error:(NSError **)error {
  RDLZipArchive *zip = [[RDLZipArchive alloc] init];
  if (![zip openData:data error:error])
    return nil;
  return zip;
}

// The end-of-central-directory record is last, but a trailing comment can push
// it back by up to 64 KB, so it has to be searched for backwards.
- (BOOL)findEndOfCentralDirectoryIn:(NSData *)data at:(NSUInteger *)outAt {
  NSUInteger length = [data length];
  if (length < kRDLEOCDMinimumLength)
    return NO;
  NSUInteger earliest =
      length > kRDLEOCDMinimumLength + kRDLMaxCommentLength
          ? length - kRDLEOCDMinimumLength - kRDLMaxCommentLength
          : 0;
  for (NSUInteger at = length - kRDLEOCDMinimumLength + 1; at-- > earliest;) {
    uint32_t sig = 0;
    if (RDLReadU32(data, at, &sig) && sig == kRDLEndOfCentralDirectorySig) {
      *outAt = at;
      return YES;
    }
  }
  return NO;
}

- (BOOL)openData:(NSData *)data error:(NSError **)error {
  if ([data length] == 0) {
    if (error)
      *error = RDLZipError(@"the file is empty");
    return NO;
  }
  NSUInteger eocd = 0;
  if (![self findEndOfCentralDirectoryIn:data at:&eocd]) {
    if (error)
      *error = RDLZipError(@"not a ZIP archive: no end-of-central-directory record");
    return NO;
  }

  uint16_t entryCount = 0;
  uint32_t directoryOffset = 0;
  if (!RDLReadU16(data, eocd + 10, &entryCount) ||
      !RDLReadU32(data, eocd + 16, &directoryOffset)) {
    if (error)
      *error = RDLZipError(@"the end-of-central-directory record is truncated");
    return NO;
  }
  // Zip64 puts 0xFFFF / 0xFFFFFFFF here and the real values in an extra
  // record. Nothing writes a .docx that large, so say so rather than
  // misreading it.
  if (entryCount == 0xFFFF || directoryOffset == 0xFFFFFFFF) {
    if (error)
      *error = RDLZipError(@"Zip64 archives are not supported");
    return NO;
  }

  _data = data;
  _names = [NSMutableArray array];
  _entries = [NSMutableDictionary dictionary];

  NSUInteger at = directoryOffset;
  for (uint16_t i = 0; i < entryCount; i++) {
    uint32_t sig = 0;
    if (!RDLReadU32(data, at, &sig) || sig != kRDLCentralFileHeaderSig) {
      if (error)
        *error = RDLZipError(@"the central directory is corrupt");
      return NO;
    }
    uint16_t method = 0, nameLength = 0, extraLength = 0, commentLength = 0;
    uint32_t compressed = 0, uncompressed = 0, localOffset = 0;
    if (!RDLReadU16(data, at + 10, &method) || !RDLReadU32(data, at + 20, &compressed) ||
        !RDLReadU32(data, at + 24, &uncompressed) || !RDLReadU16(data, at + 28, &nameLength) ||
        !RDLReadU16(data, at + 30, &extraLength) || !RDLReadU16(data, at + 32, &commentLength) ||
        !RDLReadU32(data, at + 42, &localOffset)) {
      if (error)
        *error = RDLZipError(@"a central directory entry is truncated");
      return NO;
    }
    if (at + 46 + nameLength > [data length]) {
      if (error)
        *error = RDLZipError(@"an entry name runs past the end of the file");
      return NO;
    }
    NSString *name = [[NSString alloc] initWithBytes:(const uint8_t *)[data bytes] + at + 46
                                              length:nameLength
                                            encoding:NSUTF8StringEncoding];
    if (name == nil)
      name = [[NSString alloc] initWithBytes:(const uint8_t *)[data bytes] + at + 46
                                      length:nameLength
                                    encoding:NSISOLatin1StringEncoding];
    if ([name length]) {
      RDLZipEntry *entry = [[RDLZipEntry alloc] init];
      entry.name = name;
      entry.method = method;
      entry.compressedSize = compressed;
      entry.uncompressedSize = uncompressed;
      entry.localHeaderOffset = localOffset;
      if (_entries[name] == nil)
        [_names addObject:name];
      _entries[name] = entry;
    }
    at += 46 + nameLength + extraLength + commentLength;
  }
  return YES;
}

- (NSArray<NSString *> *)entryNames {
  return _names ?: @[];
}

#pragma mark - Reading one entry

// The central directory says where the local header is; the local header says
// how much padding sits between it and the data. The two disagree about name
// and extra lengths often enough that the local header is the one to trust.
- (NSData *)compressedBytesFor:(RDLZipEntry *)entry {
  uint32_t sig = 0;
  if (!RDLReadU32(_data, entry.localHeaderOffset, &sig) || sig != kRDLLocalFileHeaderSig)
    return nil;
  uint16_t nameLength = 0, extraLength = 0;
  if (!RDLReadU16(_data, entry.localHeaderOffset + 26, &nameLength) ||
      !RDLReadU16(_data, entry.localHeaderOffset + 28, &extraLength))
    return nil;
  NSUInteger start = entry.localHeaderOffset + 30 + nameLength + extraLength;
  if (start + entry.compressedSize > [_data length])
    return nil;
  return [_data subdataWithRange:NSMakeRange(start, entry.compressedSize)];
}

// Raw deflate: a ZIP member has no zlib wrapper, which is what the negative
// window size tells inflateInit2.
static NSData *RDLInflate(NSData *input, uint32_t expectedSize) {
  if ([input length] == 0)
    return [NSData data];
  z_stream stream;
  memset(&stream, 0, sizeof(stream));
  if (inflateInit2(&stream, -MAX_WBITS) != Z_OK)
    return nil;
  stream.next_in = (Bytef *)[input bytes];
  stream.avail_in = (uInt)[input length];

  // The declared size is a hint, not a promise, so the buffer still grows.
  NSUInteger capacity = expectedSize > 0 ? expectedSize : [input length] * 4 + 1024;
  NSMutableData *out = [NSMutableData dataWithLength:capacity];
  NSUInteger written = 0;
  int status = Z_OK;
  do {
    if (written == capacity) {
      capacity *= 2;
      [out setLength:capacity];
    }
    stream.next_out = (Bytef *)[out mutableBytes] + written;
    stream.avail_out = (uInt)(capacity - written);
    status = inflate(&stream, Z_NO_FLUSH);
    if (status != Z_OK && status != Z_STREAM_END && status != Z_BUF_ERROR) {
      inflateEnd(&stream);
      return nil;
    }
    written = capacity - stream.avail_out;
    if (status == Z_BUF_ERROR && stream.avail_in == 0)
      break; // ran out of input with nothing more to give
  } while (status != Z_STREAM_END);
  inflateEnd(&stream);
  [out setLength:written];
  return out;
}

- (NSData *)dataForEntryNamed:(NSString *)name {
  RDLZipEntry *entry = _entries[name];
  if (entry == nil)
    return nil;
  NSData *raw = [self compressedBytesFor:entry];
  if (raw == nil)
    return nil;
  if (entry.method == 0) // stored
    return raw;
  if (entry.method != 8) // anything but deflate
    return nil;
  return RDLInflate(raw, entry.uncompressedSize);
}

@end

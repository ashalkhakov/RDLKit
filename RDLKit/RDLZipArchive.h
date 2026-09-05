#import <Foundation/Foundation.h>

// Just enough ZIP to read a .docx.
//
// A Word file is a ZIP of XML parts, and Foundation has no API for reading
// one, so this reads the central directory and inflates entries with zlib --
// which both macOS and GNUstep have. It reads; it does not write, and it does
// not try to be a general archiver: no encryption, no multi-disk, no Zip64.
// A .docx that needs any of those is rejected rather than half-read.
@interface RDLZipArchive : NSObject

// nil when `data` is not a ZIP this can read; `error` says why.
+ (instancetype)archiveWithData:(NSData *)data error:(NSError **)error;

// The names of the entries, in the order the archive lists them.
@property (nonatomic, readonly, copy) NSArray<NSString *> *entryNames;

// The uncompressed bytes of one entry, or nil if there is no such entry or it
// could not be inflated.
- (NSData *)dataForEntryNamed:(NSString *)name;

@end

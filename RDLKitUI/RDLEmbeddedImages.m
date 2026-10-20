/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLEmbeddedImages.h"
#import "RDLItemFactory.h"

NSArray<NSString *> *RDLImageMIMETypes(void) {
  return @[ @"image/png", @"image/jpeg", @"image/gif", @"image/bmp", @"image/x-png" ];
}

NSString *RDLImageMIMETypeForExtension(NSString *extension) {
  NSDictionary<NSString *, NSString *> *byExtension = @{
    @"png" : @"image/png",
    @"jpg" : @"image/jpeg",
    @"jpeg" : @"image/jpeg",
    @"gif" : @"image/gif",
    @"bmp" : @"image/bmp",
  };
  return byExtension[[extension lowercaseString] ?: @""];
}

// A file's name as an RDL name: letters, digits and underscores, starting with
// a letter.
static NSString *RDLNameFromFileName(NSString *fileName) {
  NSMutableString *name = [NSMutableString string];
  NSCharacterSet *allowed = [NSCharacterSet alphanumericCharacterSet];
  for (NSUInteger i = 0; i < [fileName length]; i++) {
    unichar c = [fileName characterAtIndex:i];
    BOOL ascii = c < 128 && [allowed characterIsMember:c];
    [name appendString:ascii ? [NSString stringWithCharacters:&c length:1] : @"_"];
  }
  if ([name length] == 0 || ![[NSCharacterSet letterCharacterSet] characterIsMember:[name characterAtIndex:0]])
    [name insertString:@"Image" atIndex:0];
  return name;
}

static NSError *RDLImportError(NSString *reason) {
  return [NSError errorWithDomain:@"RDLDesigner" code:1 userInfo:@{NSLocalizedDescriptionKey : reason}];
}

RDLEmbeddedImage *RDLEmbeddedImageFromFile(NSURL *url, NSArray<RDLEmbeddedImage *> *besides, NSError **error) {
  NSString *mimeType = RDLImageMIMETypeForExtension([url pathExtension]);
  if (mimeType == nil) {
    if (error)
      *error = RDLImportError([NSString stringWithFormat:@"%@ is not a PNG, JPEG, GIF or BMP picture.",
                                                         [url lastPathComponent] ?: @"The file"]);
    return nil;
  }
  NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
  if (data == nil)
    return nil;
  NSString *base = RDLNameFromFileName([[url lastPathComponent] stringByDeletingPathExtension]);
  if (![RDLItemFactory isValidName:base])
    base = @"Image";
  // Names of embedded images are compared without regard to case, as the
  // report looks them up.
  NSMutableSet<NSString *> *taken = [NSMutableSet set];
  for (RDLEmbeddedImage *image in besides)
    if (image.name)
      [taken addObject:[image.name lowercaseString]];
  NSString *name = base;
  for (NSUInteger n = 2; [taken containsObject:[name lowercaseString]]; n++)
    name = [NSString stringWithFormat:@"%@%lu", base, (unsigned long)n];
  RDLEmbeddedImage *image = [[RDLEmbeddedImage alloc] init];
  image.name = name;
  image.mimeType = mimeType;
  image.imageData = data;
  return image;
}

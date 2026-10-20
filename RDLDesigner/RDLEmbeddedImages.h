/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <Foundation/Foundation.h>
#import "RDLKit.h"

// The MIME types MS-RDL lets an image be, in the order they are offered.
FOUNDATION_EXPORT NSArray<NSString *> *RDLImageMIMETypes(void);

// The MIME type a picture file of this extension is, or nil for one MS-RDL
// cannot embed.
FOUNDATION_EXPORT NSString *RDLImageMIMETypeForExtension(NSString *extension);

// A picture file, read to be embedded in `report`: named after the file, as an
// RDL name that no other embedded image of the report has. nil, saying why,
// for a file that cannot be read or is not a kind of picture a report holds.
FOUNDATION_EXPORT RDLEmbeddedImage *RDLEmbeddedImageFromFile(NSURL *url, NSArray<RDLEmbeddedImage *> *besides,
                                                             NSError **error);

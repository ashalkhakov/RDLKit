#import "RDLBackend.h"
#import "RDLView.h"
#import "RDLReport.h"

@implementation RDLPDFBackend

- (NSString *)name {
  return @"PDF";
}

- (NSString *)pathExtension {
  return @"pdf";
}

- (NSData *)renderPages:(NSArray<RDLLaidOutPage *> *)pages title:(NSString *)title {
  (void)title;
  RDLView *view = [[RDLView alloc] initWithFrame:NSZeroRect];
  [view applyPages:pages];
  return [view PDFData];
}

@end

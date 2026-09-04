#import <Foundation/Foundation.h>
#import "RDLReport.h"

// Scaffolding a report from a Word document.
//
// The result is deliberately static: every textbox holds the text the document
// held, positioned where the document put it. Placeholders are the exception --
// `{invoice_number}` and `MERGEFIELD` become real expressions over a dataset the
// import declares -- so the report arrives knowing what data it wants, and the
// remaining work is moving boxes rather than retyping content.
//
// Heights are measured, not grown: textboxes are emitted with `CanGrow = NO`.
// A box whose height is wrong is then visibly wrong and can be dragged, rather
// than quietly reflowing the page at render time.
@interface RDLImporter : NSObject

// nil when the data is not a readable .docx; `error` says why.
+ (RDLReport *)reportFromDocxData:(NSData *)data error:(NSError **)error;

// The same, plus a list of things a person should look at: the fields that
// were found, tables that look like they want to be data regions, and anything
// that did not convert. Ordered as the document is.
+ (RDLReport *)reportFromDocxData:(NSData *)data
                            notes:(NSArray<NSString *> **)outNotes
                            error:(NSError **)error;

@end

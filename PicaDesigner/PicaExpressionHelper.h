// PicaExpressionHelper — completion support for RDL `=` expressions, in the
// spirit of an XPath editor: typing `Fields!`, `Parameters!`, `Globals!` or
// `User!` pops a member list, and elsewhere function names complete.
#import <AppKit/AppKit.h>
#import "PicaKit.h"

// Completions for the partial word in `charRange` of `text`. `dataSetName`
// scopes Fields! members (nil falls back to the report's first dataset).
NSArray<NSString *> *PicaExpressionCompletions(NSString *text, NSRange charRange,
                                               NSString *dataSetName);

// YES when the text just typed should auto-pop the completion list (an `!`
// collection accessor inside an `=` expression).
BOOL PicaShouldAutoComplete(NSString *text, NSRange selectedRange);

// GNUstep declares the completion delegate's index as `int *`, Cocoa as
// `NSInteger *`.
#ifdef GNUSTEP
typedef int PicaCompletionIndex;
#else
typedef NSInteger PicaCompletionIndex;
#endif

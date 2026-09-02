// PicaExpressionHelper — completion support for RDL `=` expressions, in the
// spirit of an XPath editor: typing `Fields!`, `Parameters!`, `Globals!` or
// `User!` pops a member list, and elsewhere function names complete.
#import <AppKit/AppKit.h>
#import "PicaKit.h"

// Completions for the partial word in `charRange` of `text`. `dataSetName`
// scopes Fields! members (nil falls back to the report's first dataset).
// The report is passed in rather than reached for, so this works for any
// document the caller happens to be editing.
NSArray<NSString *> *PicaExpressionCompletions(NSString *text, NSRange charRange,
                                               NSString *dataSetName, RDLReport *report);

// YES when the text just typed should auto-pop the completion list (an `!`
// collection accessor inside an `=` expression, or a member prefix after one).
BOOL PicaShouldAutoComplete(NSString *text, NSRange selectedRange);

// YES when the current event is ordinary typing. Auto-completion must not
// re-trigger for deletions or the arrow keys that navigate the completion
// list (Cocoa re-posts controlTextDidChange: for those).
BOOL PicaIsTypingEvent(void);

// The completion range ending at `caret`: the member prefix plus, when the
// caret sits inside a `Coll!member` accessor, the collection name and the `!`.
// Cocoa's `complete:` refuses empty partial-word ranges (it just beeps), so a
// field editor overriding -rangeForUserCompletion with this keeps the range
// non-empty right after `!`. Returns {NSNotFound, 0} when not applicable.
NSRange PicaExpressionCompletionRange(NSString *text, NSUInteger caret);

// Field editor that scopes user completion to the RDL expression grammar.
// Install from the window delegate's -windowWillReturnFieldEditor:toObject:.
@interface PicaExpressionFieldEditor : NSTextView
@end

// GNUstep declares the completion delegate's index as `int *`, Cocoa as
// `NSInteger *`.
#ifdef GNUSTEP
typedef int PicaCompletionIndex;
#else
typedef NSInteger PicaCompletionIndex;
#endif

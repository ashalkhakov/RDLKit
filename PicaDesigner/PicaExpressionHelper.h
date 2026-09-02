// PicaExpressionHelper — completion for RDL `=` expressions, in the spirit of
// an XPath editor: typing `Fields!`, `Parameters!`, `Globals!` or `User!` pops
// a member list, and elsewhere function names complete.
//
// The vocabulary and the `!`-accessor grammar are plain functions over an
// explicit scope, so they can be checked headlessly; only the field editor
// subclass and the "is this ordinary typing?" event test need AppKit state.
#import <AppKit/AppKit.h>
#import "PicaKit.h"

// The field and parameter vocabulary a completion runs against.
@interface PicaExpressionScope : NSObject
+ (instancetype)scopeWithReport:(RDLReport *)report dataSetName:(NSString *)dataSetName;
+ (instancetype)scopeWithFieldNames:(NSArray<NSString *> *)fieldNames
                     parameterNames:(NSArray<NSString *> *)parameterNames;
@property (nonatomic, readonly, copy) NSArray<NSString *> *fieldNames;
@property (nonatomic, readonly, copy) NSArray<NSString *> *parameterNames;
@end

// Completions for the partial word in `charRange` of `text`.
NSArray<NSString *> *PicaExpressionCompletions(NSString *text, NSRange charRange,
                                              PicaExpressionScope *scope);

// YES when what was just typed should pop the list unprompted: an `!`
// collection accessor inside an `=` expression, or a member prefix after one.
BOOL PicaShouldAutoComplete(NSString *text, NSRange selectedRange);

// The completion range ending at `caret`: the member prefix plus, when the
// caret sits inside a `Coll!member` accessor, the collection name and the `!`.
// Cocoa's -complete: refuses an empty partial-word range (it just beeps), so
// keeping the collection in the range is what makes completion work right
// after the `!`. Returns {NSNotFound, 0} when not applicable.
NSRange PicaExpressionCompletionRange(NSString *text, NSUInteger caret);

// The built-in function vocabulary.
NSArray<NSString *> *PicaExpressionFunctionNames(void);

// YES when the current event is ordinary typing. Auto-completion must not
// re-trigger for deletions or the arrow keys that navigate the completion
// list (Cocoa re-posts controlTextDidChange: for those).
BOOL PicaIsTypingEvent(void);

// Field editor that scopes user completion to the RDL expression grammar.
// Install from the window delegate's -windowWillReturnFieldEditor:toObject:.
//
// It also carries its OWN undo manager. A field editor with allowsUndo
// registers typing undo on whatever -undoManager returns, which by default is
// the window's -- and the designer's window vends the document's undo manager
// so Cmd+Z undoes report edits. Sharing the two breaks both: the document's
// manager groups explicitly rather than per event, and AppKit's registration
// throws against it, swallowing the keystroke. Keeping typing undo local also
// gives the better behaviour: Cmd+Z in a field undoes typing, Cmd+Z elsewhere
// undoes the document.
@interface PicaExpressionFieldEditor : NSTextView
// Call when the editor is handed to a different control, so typing undo does
// not reach back into the field previously being edited.
- (void)resetTypingUndo;
@end

// GNUstep declares the completion delegate's index as `int *`, Cocoa as
// `NSInteger *`.
#ifdef GNUSTEP
typedef int PicaCompletionIndex;
#else
typedef NSInteger PicaCompletionIndex;
#endif

#import "PicaExpressionHelper.h"

// The completion vocabulary and the `!`-accessor grammar live in PicaKit's
// RDLExpressionCompletion, which takes an explicit scope rather than reaching
// for app-wide state. This file keeps only what is genuinely UI: the field
// editor subclass and the "is this ordinary typing?" event test.

NSArray<NSString *> *PicaExpressionCompletions(NSString *text, NSRange charRange,
                                               NSString *dataSetName, RDLReport *report) {
  RDLExpressionScope *scope = [RDLExpressionScope scopeWithReport:report
                                                     dataSetName:dataSetName];
  return RDLExpressionCompletions(text, charRange, scope);
}

BOOL PicaShouldAutoComplete(NSString *text, NSRange selectedRange) {
  return RDLExpressionShouldAutoComplete(text, selectedRange);
}

NSRange PicaExpressionCompletionRange(NSString *text, NSUInteger caret) {
  return RDLExpressionCompletionRange(text, caret);
}

BOOL PicaIsTypingEvent(void) {
  NSEvent *ev = [NSApp currentEvent];
  if (ev == nil || [ev type] != NSKeyDown)
    return NO;
  NSString *chars = [ev characters];
  if ([chars length] == 0)
    return NO;
  unichar c = [chars characterAtIndex:0];
  if (c == 0x7f || c == '\b' || c == 27) // delete, backspace, escape
    return NO;
  if (c >= 0xF700 && c <= 0xF8FF) // function/arrow keys
    return NO;
  return YES;
}

@implementation PicaExpressionFieldEditor {
  NSUndoManager *_typingUndoManager;
}

// Never the window's (see the header): that one belongs to the document.
- (NSUndoManager *)undoManager {
  if (_typingUndoManager == nil)
    _typingUndoManager = [[NSUndoManager alloc] init];
  return _typingUndoManager;
}

- (void)resetTypingUndo {
  [_typingUndoManager removeAllActions];
}

- (NSRange)rangeForUserCompletion {
  NSRange r = PicaExpressionCompletionRange([self string],
                                            [self selectedRange].location);
  if (r.location != NSNotFound)
    return r;
  return [super rangeForUserCompletion];
}

@end

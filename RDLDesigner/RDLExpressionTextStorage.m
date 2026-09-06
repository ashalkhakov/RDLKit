/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLExpressionTextStorage.h"

@implementation RDLExpressionTextStorage {
  // NSTextStorage is a semi-abstract class: a subclass supplies the storage
  // and the four primitives below, and inherits everything else.
  NSMutableAttributedString *_backing;
  BOOL _colouring;
}

+ (instancetype)installedInTextView:(NSTextView *)view {
  NSLayoutManager *lm = [view layoutManager];
  if (lm == nil)
    return nil;
  RDLExpressionTextStorage *storage = [[self alloc] init];
  [storage replaceCharactersInRange:NSMakeRange(0, 0) withString:[[view textStorage] string] ?: @""];
  // -replaceTextStorage: moves every layout manager over, which is the whole
  // of what installing means; doing it by hand risks leaving the view pointing
  // at the storage it came with.
  [lm replaceTextStorage:storage];
  return [view textStorage] == storage ? storage : nil;
}

- (instancetype)init {
  // super's designated initialiser, not -initWithAttributedString:, so that
  // _backing is the one place the text lives.
  if ((self = [super init])) {
    _backing = [[NSMutableAttributedString alloc] init];
    _theme = [RDLExpressionTheme defaultTheme];
    _baseAttributes = @{
      NSFontAttributeName : [NSFont userFixedPitchFontOfSize:12] ?: [NSFont systemFontOfSize:12],
      NSForegroundColorAttributeName : [NSColor controlTextColor],
    };
  }
  return self;
}

#pragma mark - NSTextStorage primitives

- (NSString *)string {
  return [_backing string];
}

- (NSDictionary<NSString *, id> *)attributesAtIndex:(NSUInteger)location
                                     effectiveRange:(NSRangePointer)range {
  return [_backing attributesAtIndex:location effectiveRange:range];
}

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)str {
  [_backing replaceCharactersInRange:range withString:str];
  [self edited:NSTextStorageEditedCharacters
             range:range
    changeInLength:(NSInteger)[str length] - (NSInteger)range.length];
}

- (void)setAttributes:(NSDictionary<NSString *, id> *)attrs range:(NSRange)range {
  [_backing setAttributes:attrs range:range];
  [self edited:NSTextStorageEditedAttributes range:range changeInLength:0];
}

#pragma mark - Colouring

// The whole text, every time. An expression is a line or two long, and
// recolouring only the edited range would be wrong anyway: typing a quote or a
// bracket changes what the text after it is.
//
// The mask is read before -[super processEditing], which clears it, and the
// flag is there because setting attributes here is itself an edit: it comes
// back round through -edited: for a second pass, which must not colour again.
- (void)processEditing {
  NSUInteger mask = [self editedMask];
  [super processEditing];
  if (_colouring || (mask & NSTextStorageEditedCharacters) == 0)
    return;
  _colouring = YES;
  [self setAttributes:_baseAttributes range:NSMakeRange(0, [_backing length])];
  [_theme colour:self];
  _colouring = NO;
}

@end

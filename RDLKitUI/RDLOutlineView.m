/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLOutlineView.h"

BOOL RDLIsDeleteKeyEvent(NSEvent *event) {
  NSString *ch = [event charactersIgnoringModifiers];
  if ([ch length] == 0)
    return NO;
  unichar c = [ch characterAtIndex:0];
  // Backspace, the key most Mac keyboards mark "delete"; the delete character
  // the same key sends on other keyboards; and the forward-delete key, which
  // is the one a full keyboard marks "Delete" and which nothing here answered.
  return c == NSBackspaceCharacter || c == NSDeleteCharacter || c == NSDeleteFunctionKey;
}

@implementation RDLOutlineView

- (void)keyDown:(NSEvent *)event {
  if (RDLIsDeleteKeyEvent(event) &&
      [NSApp sendAction:@selector(delete:) to:nil from:self])
    return;
  [super keyDown:event];
}

@end

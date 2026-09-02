#import "PicaRichTextEditor.h"
#import "PicaRichTextCodec.h"
#import "PicaEditingContext.h"
#import "PicaCompatibility.h"

// The attributed-string <-> Paragraphs/TextRuns conversion lives in
// PicaKit's PicaRichTextCodec, where it is UI-free and covered by checks; this
// file is now just the panel around it.
@interface PicaRichTextEditor ()
@property (nonatomic, strong) IBOutlet NSWindow *window;
@property (nonatomic, strong) IBOutlet NSTextView *textView;
@property (nonatomic, strong) IBOutlet NSButton *cancelButton;
@end

@implementation PicaRichTextEditor

+ (NSAttributedString *)attributedStringForItem:(RDLItem *)item {
  return [PicaRichTextCodec attributedStringForItem:item];
}

+ (void)applyAttributedString:(NSAttributedString *)text toItem:(RDLItem *)item {
  [PicaRichTextCodec applyAttributedString:text toItem:item];
}

#pragma mark - Modal panel

- (void)accept:(id)sender {
  (void)sender;
  [NSApp stopModalWithCode:NSModalResponseOK];
  [self.window close];
}

- (void)cancel:(id)sender {
  (void)sender;
  [NSApp stopModalWithCode:NSModalResponseCancel];
  [self.window close];
}

+ (BOOL)runForTextbox:(RDLItem *)item context:(PicaEditingContext *)context {
  if (item == nil || ![item.type isEqualToString:@"Textbox"])
    return NO;
  PicaRichTextEditor *ed = [[PicaRichTextEditor alloc] init];
  // The panel -- window, hint, text view and buttons, and the releasedWhenClosed
  // NO that keeps ARC from handing AppKit a freed window -- is all in the XIB.
  NSNib *nib = [[NSNib alloc] initWithNibNamed:@"PicaRichTextEditor"
                                        bundle:[NSBundle bundleForClass:self]];
  if (![nib instantiateWithOwner:ed topLevelObjects:NULL])
    return NO;

  // Escape is the one thing the XIB cannot carry: XML forbids U+001B, as a raw
  // byte and as a character reference alike, so ibtool rejects the file outright.
  [ed.cancelButton setKeyEquivalent:@"\033"];

  [ed.window setTitle:[NSString stringWithFormat:@"Rich Text — %@", item.name]];
  NSTextView *tv = ed.textView;
  [[tv textContainer] setWidthTracksTextView:YES];
  [[tv textStorage] setAttributedString:[self attributedStringForItem:item]];
  [tv setTypingAttributes:[RDLTextAttributes attributesForStyle:item.style
                                                 paragraphAlign:nil
                                                          scale:1.0]];
  [ed.window center];
  if ([NSApp runModalForWindow:ed.window] != NSModalResponseOK)
    return NO;
  [context.editor setAttributedString:[ed.textView textStorage] ofItem:item];
  return YES;
}

@end

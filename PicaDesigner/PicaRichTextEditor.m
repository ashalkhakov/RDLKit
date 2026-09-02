#import "PicaRichTextEditor.h"
#import "PicaRichTextCodec.h"
#import "PicaEditingContext.h"
#import "PicaCompatibility.h"

// The attributed-string <-> Paragraphs/TextRuns conversion lives in
// PicaKit's PicaRichTextCodec, where it is UI-free and covered by checks; this
// file is now just the panel around it.
@interface PicaRichTextEditor ()
@property (nonatomic, strong) NSPanel *panel;
@property (nonatomic, strong) NSTextView *textView;
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
  [NSApp stopModalWithCode:1];
}

- (void)cancel:(id)sender {
  (void)sender;
  [NSApp stopModalWithCode:0];
}

+ (BOOL)runForTextbox:(RDLItem *)item context:(PicaEditingContext *)context {
  if (item == nil || ![item.type isEqualToString:@"Textbox"])
    return NO;
  PicaRichTextEditor *ed = [[PicaRichTextEditor alloc] init];
  NSRect frame = NSMakeRect(0, 0, 480, 320);
  ed.panel = [[NSPanel alloc] initWithContentRect:frame
                                        styleMask:(NSTitledWindowMask | NSResizableWindowMask)
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
  [ed.panel setTitle:[NSString stringWithFormat:@"Rich Text — %@", item.name]];
  NSView *content = [ed.panel contentView];

  NSTextField *hint = [[NSTextField alloc] initWithFrame:NSMakeRect(12, 288, 456, 20)];
  [hint setBezeled:NO];
  [hint setDrawsBackground:NO];
  [hint setEditable:NO];
  [hint setSelectable:NO];
  [hint setFont:[NSFont userFontOfSize:10]];
  [hint setStringValue:@"Cmd+B bold · Cmd+I italic · Cmd+U underline · Cmd+{ | } alignment"];
  [hint setAutoresizingMask:NSViewMinYMargin | NSViewWidthSizable];
  [content addSubview:hint];

  NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(12, 44, 456, 238)];
  [scroll setHasVerticalScroller:YES];
  [scroll setBorderType:NSBezelBorder];
  [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 440, 238)];
  [tv setRichText:YES];
  [tv setUsesFontPanel:YES];
  [tv setAllowsUndo:YES];
  [tv setVerticallyResizable:YES];
  [tv setHorizontallyResizable:NO];
  [tv setAutoresizingMask:NSViewWidthSizable];
  [[tv textContainer] setWidthTracksTextView:YES];
  [[tv textStorage] setAttributedString:[self attributedStringForItem:item]];
  [tv setTypingAttributes:[RDLTextAttributes attributesForStyle:item.style
                                              paragraphAlign:nil
                                                       scale:1.0]];
  [scroll setDocumentView:tv];
  [content addSubview:scroll];
  ed.textView = tv;

  NSButton *ok = [[NSButton alloc] initWithFrame:NSMakeRect(388, 10, 80, 26)];
  [ok setTitle:@"OK"];
  [ok setBezelStyle:NSRoundedBezelStyle];
  [ok setKeyEquivalent:@"\r"];
  [ok setTarget:ed];
  [ok setAction:@selector(accept:)];
  [ok setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
  [content addSubview:ok];
  NSButton *cancel = [[NSButton alloc] initWithFrame:NSMakeRect(300, 10, 80, 26)];
  [cancel setTitle:@"Cancel"];
  [cancel setBezelStyle:NSRoundedBezelStyle];
  [cancel setKeyEquivalent:@"\033"];
  [cancel setTarget:ed];
  [cancel setAction:@selector(cancel:)];
  [cancel setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
  [content addSubview:cancel];

  [ed.panel setInitialFirstResponder:tv];
  [ed.panel center];
  NSInteger code = [NSApp runModalForWindow:ed.panel];
  [ed.panel orderOut:nil];
  if (code != 1)
    return NO;
  [context.editor setAttributedString:[ed.textView textStorage] ofItem:item];
  return YES;
}

@end

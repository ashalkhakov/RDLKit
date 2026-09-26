/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLCodeEditor.h"
#import "RDLPane.h"

@interface RDLCodeEditor () <NSTextViewDelegate>
@property (nonatomic, strong) IBOutlet NSWindow *window;
@property (nonatomic, strong) IBOutlet NSTextView *codeText;
@property (nonatomic, strong) IBOutlet NSTextField *problemsLabel;
@end

@implementation RDLCodeEditor {
  NSArray<NSString *> *_problems;
}

+ (instancetype)editorForCode:(NSString *)code title:(NSString *)title {
  RDLCodeEditor *ed = [[self alloc] init];
  NSNib *nib = [[NSNib alloc] initWithNibNamed:@"RDLCodeEditor" bundle:[NSBundle bundleForClass:self]];
  if (![nib instantiateWithOwner:ed topLevelObjects:NULL])
    return nil;
  RDLOwnWindow(ed.window);
  if ([title length])
    [ed.window setTitle:title];
  // Code is read in columns, so it is written in them.
  NSFont *font = [NSFont userFixedPitchFontOfSize:12] ?: [NSFont systemFontOfSize:12];
  [ed.codeText setFont:font];
  // Straight quotes and dashes, which is what the language reads. Not every
  // platform substitutes them, or has the switches.
  if ([ed.codeText respondsToSelector:@selector(setAutomaticQuoteSubstitutionEnabled:)])
    [ed.codeText setAutomaticQuoteSubstitutionEnabled:NO];
  if ([ed.codeText respondsToSelector:@selector(setAutomaticDashSubstitutionEnabled:)])
    [ed.codeText setAutomaticDashSubstitutionEnabled:NO];
  if ([ed.codeText respondsToSelector:@selector(setAutomaticTextReplacementEnabled:)])
    [ed.codeText setAutomaticTextReplacementEnabled:NO];
  ed.code = code;
  return ed;
}

+ (NSString *)runForCode:(NSString *)code title:(NSString *)title {
  RDLCodeEditor *ed = [self editorForCode:code title:title];
  if (ed == nil)
    return nil;
  [ed.window center];
  NSInteger response = [NSApp runModalForWindow:ed.window];
  [ed.window orderOut:nil];
  return response == NSModalResponseOK ? ed.code : nil;
}

- (NSString *)code {
  return [[_codeText string] copy] ?: @"";
}

- (void)setCode:(NSString *)code {
  [_codeText setString:code ?: @""];
  [self check];
}

- (NSArray<NSString *> *)problems {
  return _problems ?: @[];
}

- (NSString *)status {
  return [_problemsLabel stringValue];
}

// Read by a report of its own, so what is said is what the report will say.
- (void)check {
  RDLReport *scratch = [RDLReport emptyReportNamed:@"Code"];
  scratch.code = [self code];
  _problems = [scratch codeProblems];
  NSUInteger functions = [[scratch codeFunctionNames] count];
  if ([_problems count]) {
    NSString *first = [_problems firstObject];
    [_problemsLabel setTextColor:[NSColor systemRedColor]];
    [_problemsLabel setStringValue:[_problems count] > 1
                                       ? [NSString stringWithFormat:@"%@ (and %lu more)", first,
                                                                    (unsigned long)[_problems count] - 1]
                                       : first];
    [_problemsLabel setToolTip:[_problems componentsJoinedByString:@"\n"]];
  } else {
    [_problemsLabel setTextColor:[NSColor disabledControlTextColor]];
    [_problemsLabel setStringValue:functions == 1 ? @"1 function to call."
                                                  : [NSString stringWithFormat:@"%lu functions to call.",
                                                                               (unsigned long)functions]];
    [_problemsLabel setToolTip:nil];
  }
}

- (void)textDidChange:(NSNotification *)note {
  (void)note;
  [self check];
}

- (void)accept:(id)sender {
  (void)sender;
  [NSApp stopModalWithCode:NSModalResponseOK];
}

- (void)cancel:(id)sender {
  (void)sender;
  [NSApp stopModalWithCode:NSModalResponseCancel];
}

@end

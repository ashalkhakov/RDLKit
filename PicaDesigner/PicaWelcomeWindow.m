#import "PicaWelcomeWindow.h"

NSString * const PicaOpenDesignerNotification = @"PicaOpenDesignerNotification";
NSString * const PicaOpenGeneratorNotification = @"PicaOpenGeneratorNotification";

@implementation PicaWelcomeWindow

- (instancetype)init {
  NSWindow *win = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(160, 120, 740, 420)
                styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask)
                  backing:NSBackingStoreBuffered
                    defer:NO];
  [win setTitle:@"Pica"];
  self = [super initWithWindow:win];
  if (self) {
    [self build];
  }
  return self;
}

- (void)build {
  NSView *content = [[self window] contentView];
  NSRect b = [content bounds];

  NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(28, NSHeight(b) - 56, 400, 32)];
  [title setBezeled:NO];
  [title setDrawsBackground:NO];
  [title setEditable:NO];
  [title setFont:[NSFont userFontOfSize:28]];
  [title setStringValue:@"Pica"];
  [title setAutoresizingMask:NSViewMinYMargin];
  [content addSubview:title];

  NSTextField *sub = [[NSTextField alloc] initWithFrame:NSMakeRect(28, NSHeight(b) - 100, 680, 36)];
  [sub setBezeled:NO];
  [sub setDrawsBackground:NO];
  [sub setEditable:NO];
  [sub setFont:[NSFont userFontOfSize:13]];
  [sub setStringValue:@"Two native components. Objective-C, ARC, AppKit — Cocoa and GNUstep."];
  [sub setAutoresizingMask:NSViewMinYMargin | NSViewWidthSizable];
  [content addSubview:sub];

  NSButton *gen = [[NSButton alloc] initWithFrame:NSMakeRect(28, 28, 332, 250)];
  [gen setBezelStyle:NSShadowlessSquareBezelStyle];
  [gen setAttributedTitle:[self cardTitle:@"1  Generator"
                                    body:@"Takes an RDL file, data sources, and input parameters.\nProduces PDF or HTML.\n\nPicaKit  ·  PicaDemo  ·  PicaKitTests"]];
  [gen setTarget:self];
  [gen setAction:@selector(openGenerator:)];
  [gen setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable | NSViewMaxXMargin];
  [content addSubview:gen];

  NSButton *des = [[NSButton alloc] initWithFrame:NSMakeRect(380, 28, 332, 250)];
  [des setBezelStyle:NSShadowlessSquareBezelStyle];
  [des setAttributedTitle:[self cardTitle:@"2  Designer"
                                    body:@"Create and edit RDL files.\nOutline, canvas, inspector, datasets.\n\nPica.app"]];
  [des setTarget:self];
  [des setAction:@selector(openDesigner:)];
  [des setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable | NSViewMinXMargin];
  [content addSubview:des];
}

- (NSAttributedString *)cardTitle:(NSString *)title body:(NSString *)body {
  NSMutableAttributedString *a = [[NSMutableAttributedString alloc] init];
  NSDictionary *head = @{NSFontAttributeName : [NSFont boldSystemFontOfSize:18]};
  NSDictionary *copy = @{
    NSFontAttributeName : [NSFont userFontOfSize:12],
    NSForegroundColorAttributeName : [NSColor darkGrayColor]
  };
  [a appendAttributedString:[[NSAttributedString alloc] initWithString:title attributes:head]];
  [a appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n\n" attributes:copy]];
  [a appendAttributedString:[[NSAttributedString alloc] initWithString:body attributes:copy]];
  return a;
}

- (void)openGenerator:(id)sender {
  (void)sender;
  [[NSNotificationCenter defaultCenter] postNotificationName:PicaOpenGeneratorNotification object:self];
}

- (void)openDesigner:(id)sender {
  (void)sender;
  [[NSNotificationCenter defaultCenter] postNotificationName:PicaOpenDesignerNotification object:self];
}

@end

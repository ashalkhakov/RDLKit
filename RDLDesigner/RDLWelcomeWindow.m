#import "RDLWelcomeWindow.h"

NSString * const RDLOpenDesignerNotification = @"RDLOpenDesignerNotification";
NSString * const RDLOpenGeneratorNotification = @"RDLOpenGeneratorNotification";

// The card headings and body copy are laid over their card buttons as ordinary
// labels, so their text, font and colour live in the XIB. A plain NSTextField
// there would swallow the click that is meant for the button underneath -- an
// unselectable field still answers -hitTest: -- so the labels are transparent
// to the mouse and the card behaves as one control.
//
// (Nesting the labels inside the button instead does not survive the XIB:
// ibtool drops subviews of an NSButton, which is not a container view.)
@interface RDLCardLabel : NSTextField
@end

@implementation RDLCardLabel
- (NSView *)hitTest:(NSPoint)point {
  (void)point;
  return nil;
}
@end

// Otherwise the chooser is entirely static, so it is RDLWelcomeWindow.xib in
// full and this class is just the two actions the cards send.
@interface RDLWelcomeWindow ()
@property (nonatomic, strong) IBOutlet NSButton *designerCard, *generatorCard;
@end

@implementation RDLWelcomeWindow

- (instancetype)init {
  return [super initWithWindowNibName:@"RDLWelcomeWindow"];
}

// The cards carry their text in labels laid over them, so the buttons
// themselves have no title -- which on GNUstep means they keep the one an
// NSButton starts with, and each card reads "Button" under its heading. Said
// out loud here because a XIB has no way to write an empty title: Interface
// Builder drops title="" as redundant.
- (void)windowDidLoad {
  [super windowDidLoad];
  [_designerCard setTitle:@""];
  [_generatorCard setTitle:@""];
}

- (void)openGenerator:(id)sender {
  (void)sender;
  [[NSNotificationCenter defaultCenter] postNotificationName:RDLOpenGeneratorNotification object:self];
}

- (void)openDesigner:(id)sender {
  (void)sender;
  [[NSNotificationCenter defaultCenter] postNotificationName:RDLOpenDesignerNotification object:self];
}

@end

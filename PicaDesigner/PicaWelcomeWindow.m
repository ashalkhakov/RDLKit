#import "PicaWelcomeWindow.h"

NSString * const PicaOpenDesignerNotification = @"PicaOpenDesignerNotification";
NSString * const PicaOpenGeneratorNotification = @"PicaOpenGeneratorNotification";

// The card headings and body copy are laid over their card buttons as ordinary
// labels, so their text, font and colour live in the XIB. A plain NSTextField
// there would swallow the click that is meant for the button underneath -- an
// unselectable field still answers -hitTest: -- so the labels are transparent
// to the mouse and the card behaves as one control.
//
// (Nesting the labels inside the button instead does not survive the XIB:
// ibtool drops subviews of an NSButton, which is not a container view.)
@interface PicaCardLabel : NSTextField
@end

@implementation PicaCardLabel
- (NSView *)hitTest:(NSPoint)point {
  (void)point;
  return nil;
}
@end

// Otherwise the chooser is entirely static, so it is PicaWelcomeWindow.xib in
// full and this class is just the two actions the cards send.
@implementation PicaWelcomeWindow

- (instancetype)init {
  return [super initWithWindowNibName:@"PicaWelcomeWindow"];
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

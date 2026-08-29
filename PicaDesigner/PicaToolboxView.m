#import "PicaToolboxView.h"
#import "PicaController.h"

@implementation PicaToolboxView {
  NSMutableArray *_buttons;
  BOOL _reloading;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _buttons = [NSMutableArray array];
    NSArray *titles = @[ @"Sel", @"Abc", @"—", @"□", @"Img", @"Tbl", @"Ch" ];
    NSArray *tips = @[ @"Select", @"Text box", @"Line", @"Rectangle", @"Image", @"Tablix", @"Chart" ];
    CGFloat y = 8;
    for (NSInteger i = 0; i < 7; i++) {
      NSButton *b = [[NSButton alloc] initWithFrame:NSMakeRect(6, y, 36, 32)];
      [b setTitle:titles[i]];
      [b setButtonType:NSToggleButton];
      [b setBezelStyle:NSShadowlessSquareBezelStyle];
      [b setTag:i];
      [b setTarget:self];
      [b setAction:@selector(pick:)];
      [b setToolTip:tips[i]];
      [b setAutoresizingMask:NSViewMinYMargin];
      [b setFont:[NSFont userFontOfSize:10]];
      [self addSubview:b];
      [_buttons addObject:b];
      y += 36;
    }
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reload)
                                                 name:PicaSelectionDidChangeNotification
                                               object:nil];
    [self reload];
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)isFlipped {
  return YES;
}

- (void)pick:(NSButton *)sender {
  if (_reloading)
    return;
  [PicaController sharedController].tool = (PicaTool)[sender tag];
  [self reload];
}

- (void)reload {
  if (_reloading)
    return;
  _reloading = YES;
  PicaTool t = [PicaController sharedController].tool;
  for (NSButton *b in _buttons)
    [b setState:([b tag] == t) ? NSOnState : NSOffState];
  _reloading = NO;
}

@end

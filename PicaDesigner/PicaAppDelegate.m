#import "PicaAppDelegate.h"
#import "PicaDesignerWindow.h"
#import "PicaGeneratorWindow.h"
#import "PicaWelcomeWindow.h"
#import "PicaController.h"
#import "PicaSamples.h"

@implementation PicaAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)n {
  (void)n;
  [self buildMenu];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(showDesigner:)
                                               name:PicaOpenDesignerNotification
                                             object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(showGenerator:)
                                               name:PicaOpenGeneratorNotification
                                             object:nil];
  [self showLibrary:nil];
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSMenuItem *)item:(NSString *)title action:(SEL)sel key:(NSString *)key {
  NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:title action:sel keyEquivalent:key ?: @""];
  [it setTarget:self];
  return it;
}

// Nil-target item: the action goes to the first responder (field editor,
// canvas, window undo manager…) instead of the app delegate.
- (NSMenuItem *)responderItem:(NSString *)title action:(SEL)sel key:(NSString *)key {
  return [[NSMenuItem alloc] initWithTitle:title action:sel keyEquivalent:key ?: @""];
}

- (void)buildMenu {
  NSMenu *menubar = [[NSMenu alloc] initWithTitle:@""];
  NSMenuItem *appItem = [[NSMenuItem alloc] init];
  [menubar addItem:appItem];
  NSMenu *app = [[NSMenu alloc] initWithTitle:@"Pica"];
  NSMenuItem *about = [[NSMenuItem alloc] initWithTitle:@"About Pica"
                                                 action:@selector(orderFrontStandardAboutPanel:)
                                          keyEquivalent:@""];
  [about setTarget:NSApp];
  [app addItem:about];
  [app addItem:[NSMenuItem separatorItem]];
  NSMenuItem *quit = [self item:@"Quit Pica" action:@selector(terminate:) key:@"q"];
  [quit setTarget:NSApp];
  [app addItem:quit];
  [appItem setSubmenu:app];

  NSMenuItem *fileItem = [[NSMenuItem alloc] init];
  [menubar addItem:fileItem];
  NSMenu *file = [[NSMenu alloc] initWithTitle:@"File"];
  [file addItem:[self item:@"Library…" action:@selector(showLibrary:) key:@"l"]];
  [file addItem:[self item:@"Generator" action:@selector(showGenerator:) key:@""]];
  [file addItem:[self item:@"Designer" action:@selector(showDesigner:) key:@""]];
  [file addItem:[NSMenuItem separatorItem]];
  [file addItem:[self item:@"New Letter" action:@selector(newDocument:) key:@"n"]];
  [file addItem:[self item:@"Open…" action:@selector(openDocument:) key:@"o"]];
  [file addItem:[self item:@"Save" action:@selector(saveDocument:) key:@"s"]];
  [file addItem:[self item:@"Save As…" action:@selector(saveDocumentAs:) key:@"S"]];
  [file addItem:[NSMenuItem separatorItem]];
  NSMenuItem *samplesItem = [[NSMenuItem alloc] initWithTitle:@"Samples" action:NULL keyEquivalent:@""];
  NSMenu *samples = [[NSMenu alloc] initWithTitle:@"Samples"];
  NSArray *cat = [PicaSamples catalog];
  for (NSInteger i = 0; i < (NSInteger)[cat count]; i++) {
    NSMenuItem *si = [[NSMenuItem alloc] initWithTitle:cat[i][@"title"]
                                                action:@selector(openSample:)
                                         keyEquivalent:@""];
    [si setTag:i];
    [si setTarget:self];
    [samples addItem:si];
  }
  [samplesItem setSubmenu:samples];
  [file addItem:samplesItem];
  [file addItem:[NSMenuItem separatorItem]];
  [file addItem:[self item:@"Preview" action:@selector(preview:) key:@"p"]];
  [file addItem:[self item:@"Export PDF…" action:@selector(exportPDF:) key:@"e"]];
  [fileItem setSubmenu:file];

  NSMenuItem *editItem = [[NSMenuItem alloc] init];
  [menubar addItem:editItem];
  NSMenu *edit = [[NSMenu alloc] initWithTitle:@"Edit"];
  // Standard editing items dispatch through the responder chain (nil target);
  // without them Cmd+Z/X/C/V/A never reach text fields or the undo manager.
  [edit addItem:[self responderItem:@"Undo" action:@selector(undo:) key:@"z"]];
  [edit addItem:[self responderItem:@"Redo" action:@selector(redo:) key:@"Z"]];
  [edit addItem:[NSMenuItem separatorItem]];
  [edit addItem:[self responderItem:@"Cut" action:@selector(cut:) key:@"x"]];
  [edit addItem:[self responderItem:@"Copy" action:@selector(copy:) key:@"c"]];
  [edit addItem:[self responderItem:@"Paste" action:@selector(paste:) key:@"v"]];
  [edit addItem:[self responderItem:@"Select All" action:@selector(selectAll:) key:@"a"]];
  [edit addItem:[NSMenuItem separatorItem]];
  [edit addItem:[self item:@"Add Element…" action:@selector(addElement:) key:@"A"]];
  [edit addItem:[self item:@"Delete" action:@selector(delete:) key:@"\b"]];
  [edit addItem:[self item:@"Toggle Grid" action:@selector(toggleGrid:) key:@"g"]];
  [edit addItem:[self item:@"Zoom In" action:@selector(zoomIn:) key:@"="]];
  [edit addItem:[self item:@"Zoom Out" action:@selector(zoomOut:) key:@"-"]];
  [editItem setSubmenu:edit];

  [NSApp setMainMenu:menubar];
}

- (void)ensureDesigner {
  if (_designer == nil)
    _designer = [[PicaDesignerWindow alloc] init];
}

- (void)ensureGenerator {
  if (_generator == nil) {
    _generator = [[PicaGeneratorWindow alloc] init];
    [_generator loadSample:@"invoice"];
  }
}

- (void)showDesigner:(id)sender {
  (void)sender;
  [self ensureDesigner];
  [[_designer window] makeKeyAndOrderFront:nil];
  [[_welcome window] orderOut:nil];
}

- (void)showGenerator:(id)sender {
  (void)sender;
  [self ensureGenerator];
  [[_generator window] makeKeyAndOrderFront:nil];
  [[_welcome window] orderOut:nil];
}

- (void)showLibrary:(id)sender {
  (void)sender;
  if (_welcome == nil)
    _welcome = [[PicaWelcomeWindow alloc] init];
  [[_welcome window] makeKeyAndOrderFront:nil];
}

- (BOOL)generatorIsFront {
  return _generator != nil && [[_generator window] isKeyWindow];
}

- (void)openSample:(NSMenuItem *)sender {
  NSArray *cat = [PicaSamples catalog];
  NSInteger i = [sender tag];
  if (i < 0 || i >= (NSInteger)[cat count])
    return;
  if ([self generatorIsFront]) {
    [_generator loadSample:cat[i][@"id"]];
    return;
  }
  [[PicaController sharedController] loadSample:cat[i][@"id"]];
  [self showDesigner:nil];
}

- (void)newDocument:(id)sender {
  (void)sender;
  [[PicaController sharedController] newReport];
  [self showDesigner:nil];
}

- (void)openDocument:(id)sender {
  (void)sender;
  if ([self generatorIsFront]) {
    [_generator openRdl:sender];
    return;
  }
  NSOpenPanel *p = [NSOpenPanel openPanel];
  [p setAllowedFileTypes:@[ @"rdl", @"rdlc", @"xml" ]];
  [p setCanChooseFiles:YES];
  [p setCanChooseDirectories:NO];
  if ([p runModal] == NSOKButton) {
    NSError *err = nil;
    if (![[PicaController sharedController] openURL:[p URL] error:&err]) {
      NSAlert *a = [[NSAlert alloc] init];
      [a setMessageText:@"Could not open RDL"];
      [a setInformativeText:err.localizedDescription ?: @""];
      [a runModal];
      return;
    }
    [self showDesigner:nil];
  }
}

- (void)saveDocument:(id)sender {
  PicaController *c = [PicaController sharedController];
  if (c.fileURL) {
    NSError *err = nil;
    [c saveToURL:c.fileURL error:&err];
    return;
  }
  [self saveDocumentAs:sender];
}

- (void)saveDocumentAs:(id)sender {
  (void)sender;
  [self ensureDesigner];
  NSSavePanel *p = [NSSavePanel savePanel];
  [p setAllowedFileTypes:@[ @"rdl" ]];
  [p setNameFieldStringValue:
      [([PicaController sharedController].report.name ?: @"report") stringByAppendingPathExtension:@"rdl"]];
  if ([p runModal] == NSOKButton) {
    NSError *err = nil;
    [[PicaController sharedController] saveToURL:[p URL] error:&err];
  }
}

- (void)preview:(id)sender {
  if ([self generatorIsFront])
    return;
  [self ensureDesigner];
  [_designer showPreview:sender];
}

- (void)exportPDF:(id)sender {
  if ([self generatorIsFront]) {
    [_generator exportPDF:sender];
    return;
  }
  [self ensureDesigner];
  [_designer exportPDF:sender];
}

- (void)delete:(id)sender {
  (void)sender;
  [[PicaController sharedController] removeSelected];
}

- (void)addElement:(id)sender {
  if ([self generatorIsFront])
    return;
  [self ensureDesigner];
  [[_designer window] makeKeyAndOrderFront:nil];
  [_designer addElement:sender];
}

- (void)toggleGrid:(id)sender {
  (void)sender;
  PicaController *c = [PicaController sharedController];
  c.showsGrid = !c.showsGrid;
  [c noteChange];
  c.dirty = NO;
}

- (void)zoomIn:(id)sender {
  (void)sender;
  PicaController *c = [PicaController sharedController];
  c.zoom = MIN(2.0, c.zoom + 0.1);
  [c noteChange];
  c.dirty = NO;
}

- (void)zoomOut:(id)sender {
  (void)sender;
  PicaController *c = [PicaController sharedController];
  c.zoom = MAX(0.4, c.zoom - 0.1);
  [c noteChange];
  c.dirty = NO;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app {
  (void)app;
  return YES;
}

@end

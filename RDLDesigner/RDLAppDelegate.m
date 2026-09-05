#import "RDLAppDelegate.h"
#import "RDLDesignerWindow.h"
#import "RDLGeneratorWindow.h"
#import "RDLWelcomeWindow.h"
#import "RDLEditingContext.h"
#import "RDLNewReportPanel.h"
#import "RDLSamples.h"

@implementation RDLAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)n {
  (void)n;
  _context = [[RDLEditingContext alloc] init];
  [self loadMenuBar];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(newReportThenDesigner:)
                                               name:RDLOpenDesignerNotification
                                             object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(showGenerator:)
                                               name:RDLOpenGeneratorNotification
                                             object:nil];
  [self showLibrary:nil];
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// The menu bar is MainMenu.xib. Its items are wired there: the ones this class
// implements to File's Owner, and the editing ones (Undo, Cut, Open…, Export
// PDF…) to First Responder, so the front window or the field editor answers
// them before this fallback does.
- (void)loadMenuBar {
  NSNib *nib = [[NSNib alloc] initWithNibNamed:@"MainMenu" bundle:[NSBundle mainBundle]];
  [nib instantiateWithOwner:self topLevelObjects:NULL];
  [self populateSamplesMenu];
  [NSApp setMainMenu:_mainMenu];
}

- (void)populateSamplesMenu {
  [_samplesMenu removeAllItems];
  NSArray *catalog = [RDLSamples catalog];
  for (NSInteger i = 0; i < (NSInteger)[catalog count]; i++) {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:catalog[i][@"title"]
                                                  action:@selector(openSample:)
                                           keyEquivalent:@""];
    [item setTag:i];
    [item setTarget:self];
    [_samplesMenu addItem:item];
  }
}

- (void)ensureDesigner {
  if (_designer == nil)
    _designer = [[RDLDesignerWindow alloc] initWithContext:_context];
}

- (void)ensureGenerator {
  if (_generator == nil)
    _generator = [[RDLGeneratorWindow alloc] initWithDocument:_context.document];
}

// Making a new report, from the welcome screen's Designer card and from File >
// New Report. Both ask the same question and land in the same place, because a
// report has to come from somewhere and "from a Word document I already have"
// is as reasonable a starting point as an empty page.
//
// Cancelling leaves the user exactly where they were: no report is loaded and
// no window is brought forward.
//
// Only these two entry points go through the wizard. Opening a file, or
// anything else that already has a report in hand, calls -showDesigner:
// directly.
- (void)newReportThenDesigner:(id)sender {
  (void)sender;
  RDLNewReportOutcome *outcome = [RDLNewReportPanel run];
  if (outcome == nil)
    return;
  [_context loadReport:outcome.report];
  [self showDesigner:nil];
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
    _welcome = [[RDLWelcomeWindow alloc] init];
  [[_welcome window] makeKeyAndOrderFront:nil];
}

- (void)openSample:(NSMenuItem *)sender {
  NSArray *cat = [RDLSamples catalog];
  NSInteger i = [sender tag];
  if (i < 0 || i >= (NSInteger)[cat count])
    return;
  // One document, so the sample lands wherever the user is looking.
  [_context loadSampleWithId:cat[i][@"id"]];
  if (![[_generator window] isKeyWindow])
    [self showGenerator:nil];
}

// File > New Report. It used to make a blank Letter report and open the
// generator; it now asks the same question the welcome screen does, and opens
// the designer, since a report that has just been made has nothing to run yet
// and a scaffolded one needs its boxes moved.
- (void)newDocument:(id)sender {
  [self newReportThenDesigner:sender];
}

// Only reached when no window handled it -- each window controller implements
// -openDocument: for itself, and the responder chain gets there first.
- (void)openDocument:(id)sender {
  (void)sender;
  NSOpenPanel *p = [NSOpenPanel openPanel];
  [p setAllowedFileTypes:@[ @"rdl", @"rdlc", @"xml" ]];
  [p setCanChooseFiles:YES];
  [p setCanChooseDirectories:NO];
  if ([p runModal] == NSOKButton) {
    NSError *err = nil;
    if (![_context.document openURL:[p URL] error:&err]) {
      NSAlert *a = [[NSAlert alloc] init];
      [a setMessageText:@"Could not open RDL"];
      [a setInformativeText:err.localizedDescription ?: @""];
      [a runModal];
      return;
    }
    // The old report's items are gone with it.
    [_context.selection reset];
    [self showDesigner:nil];
  }
}

- (void)saveDocument:(id)sender {
  if (_context.document.fileURL) {
    NSError *err = nil;
    if (![_context.document saveWithError:&err])
      [self presentError:err title:@"Could not save RDL"];
    return;
  }
  [self saveDocumentAs:sender];
}

- (void)presentError:(NSError *)error title:(NSString *)title {
  NSAlert *a = [[NSAlert alloc] init];
  [a setMessageText:title];
  [a setInformativeText:error.localizedDescription ?: @""];
  [a runModal];
}

- (void)saveDocumentAs:(id)sender {
  (void)sender;
  [self ensureDesigner];
  NSSavePanel *p = [NSSavePanel savePanel];
  [p setAllowedFileTypes:@[ @"rdl" ]];
  [p setNameFieldStringValue:
          [(_context.report.name ?: @"report") stringByAppendingPathExtension:@"rdl"]];
  if ([p runModal] == NSOKButton) {
    NSError *err = nil;
    if (![_context.document saveToURL:[p URL] error:&err])
      [self presentError:err title:@"Could not save RDL"];
  }
}

// Fallbacks for when the front window does not handle these itself.
- (void)preview:(id)sender {
  [self ensureDesigner];
  [_designer showPreview:sender];
}

- (void)exportPDF:(id)sender {
  [self ensureDesigner];
  [_designer exportPDF:sender];
}

- (void)delete:(id)sender {
  (void)sender;
  [_context deleteSelectedItem];
}

- (void)addElement:(id)sender {
  [self ensureDesigner];
  [[_designer window] makeKeyAndOrderFront:nil];
  [_designer addElement:sender];
}

- (void)toggleGrid:(id)sender {
  (void)sender;
  [_context toggleGrid];
}

- (void)zoomIn:(id)sender {
  (void)sender;
  [_context zoomIn];
}

- (void)zoomOut:(id)sender {
  (void)sender;
  [_context zoomOut];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app {
  (void)app;
  return YES;
}

@end

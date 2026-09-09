#import "RDLAppDelegate.h"
#import "RDLDesignerWindow.h"
#import "RDLDocument.h"
#import "RDLGeneratorWindow.h"
#import "RDLWelcomeWindow.h"
#import "RDLEditingContext.h"
#import "RDLNewReportPanel.h"
#import "RDLSamples.h"

@implementation RDLAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)n {
  (void)n;
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

// The library is what opens at launch, not an empty report: a person arriving
// with nothing in mind is offered the samples and the recent files rather than
// a blank page they did not ask for.
- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)app {
  (void)app;
  return NO;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// The menu bar is MainMenu.xib. Its items are wired there: the ones this class
// implements to File's Owner, and the editing ones (Undo, Cut, Open…, Export
// PDF…) to First Responder, so the front window, the document, or the field
// editor answers them before this fallback does.
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

#pragma mark - Which report is in front

- (RDLDocument *)currentDocument {
  NSDocument *doc = [[NSDocumentController sharedDocumentController] currentDocument];
  return [doc isKindOfClass:[RDLDocument class]] ? (RDLDocument *)doc : nil;
}

- (RDLEditingContext *)currentContext {
  return [self currentDocument].context;
}

// A report that came from somewhere other than a file -- a sample, the new
// report panel, an imported Word document -- still opens as a document, so it
// saves, undoes and closes like any other.
- (RDLDocument *)openDocumentWithReport:(RDLReport *)report {
  return [self openDocumentWithReport:report originURL:nil];
}

- (RDLDocument *)openDocumentWithReport:(RDLReport *)report originURL:(NSURL *)originURL {
  RDLDocument *doc = [[RDLDocument alloc] initWithReport:report];
  // A sample is untitled -- Save asks where to put it -- but the documents it
  // names are beside the file it came out of, so it remembers that folder.
  doc.originURL = originURL;
  [[NSDocumentController sharedDocumentController] addDocument:doc];
  [doc makeWindowControllers];
  [doc showWindows];
  [[_welcome window] orderOut:nil];
  return doc;
}

#pragma mark - Opening

// Making a new report, from the welcome screen's Designer card and from File >
// New Report. Both ask the same question and land in the same place, because a
// report has to come from somewhere and "from a Word document I already have"
// is as reasonable a starting point as an empty page.
//
// Cancelling leaves the user exactly where they were: nothing is opened and no
// window is brought forward.
- (void)newReportThenDesigner:(id)sender {
  (void)sender;
  RDLNewReportOutcome *outcome = [RDLNewReportPanel run];
  if (outcome == nil)
    return;
  [self openDocumentWithReport:outcome.report];
}

// File > New Report. It asks the same question the welcome screen does rather
// than making a blank Letter report, since a report that has just been made
// has nothing to run yet and a scaffolded one needs its boxes moved.
- (void)newDocument:(id)sender {
  [self newReportThenDesigner:sender];
}

- (void)openSample:(NSMenuItem *)sender {
  NSArray *cat = [RDLSamples catalog];
  NSInteger i = [sender tag];
  if (i < 0 || i >= (NSInteger)[cat count])
    return;
  // A sample opens as its own document, beside whatever else is open, so
  // looking at one does not close the report someone was working on. Opening
  // one used to run it, which is a different thing to ask for: the generator
  // is one window away when the answer is wanted.
  NSString *sampleId = cat[(NSUInteger)i][@"id"];
  RDLReport *report = [RDLSamples reportWithId:sampleId];
  if (report == nil) {
    [self presentError:[NSError errorWithDomain:@"RDLDesigner" code:1 userInfo:@{
                         NSLocalizedDescriptionKey :
                             [NSString stringWithFormat:@"The sample file for '%@' is missing "
                                                        @"from this application.", sampleId]}]
                 title:@"Could not open the sample"];
    return;
  }
  [self openDocumentWithReport:report originURL:[RDLSamples URLForSampleWithId:sampleId]];
}

- (void)showDesigner:(id)sender {
  (void)sender;
  RDLDocument *doc = [self currentDocument];
  if (doc == nil) {
    [self newReportThenDesigner:sender];
    return;
  }
  [doc showWindows];
  [[_welcome window] orderOut:nil];
}

- (void)showGenerator:(id)sender {
  (void)sender;
  RDLDocument *doc = [self currentDocument];
  if (doc == nil)
    doc = [self openDocumentWithReport:[RDLSamples blankLetter]];
  // The generator follows the report in front: opening it on a different one
  // means a different window, not a window that quietly swapped its report.
  if (_generator != nil && _generator.reportDocument != doc) {
    [[_generator window] close];
    _generator = nil;
  }
  if (_generator == nil)
    _generator = [[RDLGeneratorWindow alloc] initWithDocument:doc];
  [[_generator window] makeKeyAndOrderFront:nil];
  [[_welcome window] orderOut:nil];
}

- (void)showLibrary:(id)sender {
  (void)sender;
  if (_welcome == nil)
    _welcome = [[RDLWelcomeWindow alloc] init];
  [[_welcome window] makeKeyAndOrderFront:nil];
}

#pragma mark - Menu fallbacks

// Reached only when no window handled them: the front designer window answers
// these first, and File > Open, Save and Close are the document architecture's
// own. What is left here is what to do when a report is expected and there is
// none.

- (void)presentError:(NSError *)error title:(NSString *)title {
  NSAlert *a = [[NSAlert alloc] init];
  [a setMessageText:title];
  [a setInformativeText:error.localizedDescription ?: @""];
  [a runModal];
}

- (void)preview:(id)sender {
  for (NSWindowController *wc in [[self currentDocument] windowControllers])
    if ([wc isKindOfClass:[RDLDesignerWindow class]]) {
      [(RDLDesignerWindow *)wc showPreview:sender];
      return;
    }
}

- (void)exportPDF:(id)sender {
  for (NSWindowController *wc in [[self currentDocument] windowControllers])
    if ([wc isKindOfClass:[RDLDesignerWindow class]]) {
      [(RDLDesignerWindow *)wc exportPDF:sender];
      return;
    }
}

- (void)delete:(id)sender {
  (void)sender;
  [[self currentContext] deleteSelectedItem];
}

- (void)addElement:(id)sender {
  for (NSWindowController *wc in [[self currentDocument] windowControllers])
    if ([wc isKindOfClass:[RDLDesignerWindow class]]) {
      [[wc window] makeKeyAndOrderFront:nil];
      [(RDLDesignerWindow *)wc addElement:sender];
      return;
    }
}

- (void)toggleGrid:(id)sender {
  (void)sender;
  [[self currentContext] toggleGrid];
}

- (void)zoomIn:(id)sender {
  (void)sender;
  [[self currentContext] zoomIn];
}

- (void)zoomOut:(id)sender {
  (void)sender;
  [[self currentContext] zoomOut];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app {
  (void)app;
  return YES;
}

@end

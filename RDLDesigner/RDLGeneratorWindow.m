#import "RDLGeneratorWindow.h"
#import "RDLDocument.h"
#import "RDLChange.h"
#import "RDLDataView.h"
#import "RDLSamples.h"
#import "RDLCompatibility.h"
#import "RDLKit.h"

@interface RDLGeneratorWindow ()
@property (nonatomic, strong, readwrite) RDLDocument *reportDocument;
@property (nonatomic, strong) IBOutlet RDLView *preview;
@property (nonatomic, strong) IBOutlet RDLDataView *dataView;
@property (nonatomic, strong) IBOutlet NSPopUpButton *samplePopup;
@property (nonatomic, strong) IBOutlet NSButton *remoteCheck;
@property (nonatomic, strong) IBOutlet NSTextField *dataStatus;
@property (nonatomic, strong) IBOutlet NSSplitView *split;
@end

@implementation RDLGeneratorWindow

- (instancetype)initWithDocument:(RDLDocument *)document {
  self = [super initWithWindowNibName:@"RDLGeneratorWindow"];
  if (self) {
    // Set before -window pulls the nib in, so -windowDidLoad can pass it on.
    _reportDocument = document;
    [self window];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(documentDidChange:)
                                                 name:RDLDocumentDidChangeNotification
                                               object:document];
    [self updateForDocument];
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)documentDidChange:(NSNotification *)note {
  RDLChange *change = [note userInfo][RDLChangeKey];
  // Anything that can alter the output re-lays out; a plain rename does not.
  if ([change affectsLayout])
    [self reloadPreview];
  [self updateWindowTitle];
}

#pragma mark - UI

// RDLGeneratorWindow.xib holds the window, the toolbar row, the split and
// both panes. Two things are not fixed: the sample list, which comes from the
// sample catalog, and one export button per backend the kit offers -- so
// adding a backend still needs no change here.
- (void)windowDidLoad {
  [super windowDidLoad];
  // The window controller is the window's delegate (wired in the XIB), which
  // puts it in the responder chain: menu actions with a nil target reach
  // whichever window is in front, so the app delegate need not ask which.
  _dataView.document = _reportDocument;

  for (NSDictionary *sample in [RDLSamples catalog])
    [_samplePopup addItemWithTitle:sample[@"title"]];

  NSView *content = [[self window] contentView];
  CGFloat top = NSHeight([content bounds]) - 36;
  CGFloat x = NSWidth([content bounds]) - 90;
  for (id<RDLBackend> backend in [_reportDocument exportBackends]) {
    NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(x, top, 80, 26)];
    [button setTitle:[backend.pathExtension uppercaseString]];
    [button setBezelStyle:NSRoundedBezelStyle];
    [button setTarget:self];
    [button setAction:@selector(exportFrontmost:)];
    [button setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
    [content addSubview:button];
    x -= 90;
  }
}

- (void)reloadPreview {
  _preview.report = _reportDocument.report;
  _preview.paramValues = _reportDocument.paramValues;
  [_preview reloadLayout];
}

- (void)updateWindowTitle {
  [[self window] setTitle:[NSString stringWithFormat:@"RDLDesigner Generator — %@",
                                                     _reportDocument.report.name ?: @"Report"]];
}

- (void)updateForDocument {
  [_dataView reload];
  [self reloadPreview];
  [self updateWindowTitle];
}

#pragma mark - Loading

- (void)samplePicked:(NSPopUpButton *)sender {
  NSInteger i = [sender indexOfSelectedItem] - 1;
  NSArray *catalog = [RDLSamples catalog];
  if (i >= 0 && i < (NSInteger)[catalog count]) {
    NSString *sampleId = catalog[(NSUInteger)i][@"id"];
    [_reportDocument loadReport:[RDLSamples reportWithId:sampleId]
                      originURL:[RDLSamples URLForSampleWithId:sampleId]];
    [self updateForDocument];
  }
  [sender selectItemAtIndex:0];
}

- (void)openRdl:(id)sender {
  RDL_UNUSED(sender);
  [self openDocument:sender];
}

// A menu action too: this window is in the responder chain.
- (void)openDocument:(id)sender {
  RDL_UNUSED(sender);
  NSOpenPanel *p = [NSOpenPanel openPanel];
  [p setAllowedFileTypes:@[ @"rdl", @"rdlc", @"xml" ]];
  [p setCanChooseFiles:YES];
  [p setCanChooseDirectories:NO];
  if ([p runModal] != NSOKButton)
    return;
  NSError *err = nil;
  if (![_reportDocument openURL:[p URL] error:&err]) {
    [self presentError:err title:@"Could not open RDL"];
    return;
  }
  [self updateForDocument];
}

// Every data source the report names, not the first dataset: a report with
// three datasets needs three documents, and one that cannot be read should not
// stop the others.
- (NSString *)readDataFetchingRemote:(BOOL)fetchRemote {
  NSArray<NSString *> *notes = nil;
  NSError *err = nil;
  [_reportDocument bindDataSourcesFetchingRemote:fetchRemote notes:&notes error:&err];
  NSUInteger rows = 0, bound = 0;
  for (RDLDataSet *ds in _reportDocument.report.dataSets) {
    if ([ds.rows count]) {
      bound += 1;
      rows += [ds.rows count];
    }
  }
  NSString *summary =
      [NSString stringWithFormat:@"%lu dataset%@ read, %lu row%@", (unsigned long)bound,
                                 bound == 1 ? @"" : @"s", (unsigned long)rows,
                                 rows == 1 ? @"" : @"s"];
  if ([notes count])
    summary = [summary stringByAppendingFormat:@" — %@",
                                               [notes componentsJoinedByString:@"; "]];
  [_dataStatus setStringValue:summary];
  [self updateForDocument];
  return summary;
}

- (void)bindData:(id)sender {
  RDL_UNUSED(sender);
  [self readDataFetchingRemote:[_remoteCheck state] == NSOnState];
  // A report written elsewhere names documents by paths that mean nothing
  // here, so rather than reporting that and stopping, offer to go and find
  // each one. Answering the panel is what tells the report where its data is.
  for (RDLDataSource *source in [_reportDocument unreadableDataSources]) {
    NSOpenPanel *p = [NSOpenPanel openPanel];
    [p setCanChooseFiles:YES];
    [p setCanChooseDirectories:NO];
    [p setTitle:[NSString stringWithFormat:@"Find the document for '%@'", source.name ?: @""]];
    [p setMessage:[NSString stringWithFormat:@"'%@' reads %@, which is not where the report "
                                             @"says it is.",
                                             source.name ?: @"",
                                             source.connectString ?: @""]];
    if ([p runModal] != NSOKButton)
      continue;
    [_reportDocument setDocumentPath:[[p URL] path] forDataSourceNamed:source.name];
    [self readDataFetchingRemote:[_remoteCheck state] == NSOnState];
  }
}

#pragma mark - Export

- (void)exportFrontmost:(NSButton *)sender {
  // The button's title is the backend's extension, so one action serves all.
  [self exportUsingBackend:
            [_reportDocument exportBackendForPathExtension:[[sender title] lowercaseString]]];
}

- (void)exportPDF:(id)sender {
  RDL_UNUSED(sender);
  [self exportUsingBackend:[_reportDocument exportBackendForPathExtension:@"pdf"]];
}

- (void)exportHTML:(id)sender {
  RDL_UNUSED(sender);
  [self exportUsingBackend:[_reportDocument exportBackendForPathExtension:@"html"]];
}

- (void)exportUsingBackend:(id<RDLBackend>)backend {
  if (backend == nil)
    return;
  NSMutableArray *types = [NSMutableArray array];
  for (id<RDLBackend> b in [_reportDocument exportBackends])
    [types addObject:b.pathExtension];
  NSSavePanel *p = [NSSavePanel savePanel];
  [p setAllowedFileTypes:types];
  [p setNameFieldStringValue:[_reportDocument suggestedFileNameForBackend:backend]];
  if ([p runModal] != NSOKButton)
    return;
  NSURL *url = [p URL];
  id<RDLBackend> chosen =
      [_reportDocument exportBackendForPathExtension:[url pathExtension]] ?: backend;
  NSError *err = nil;
  if (![_reportDocument exportUsingBackend:chosen toURL:url error:&err])
    [self presentError:err title:@"Could not export"];
}

- (void)presentError:(NSError *)error title:(NSString *)title {
  NSAlert *a = [[NSAlert alloc] init];
  [a setMessageText:title];
  [a setInformativeText:error.localizedDescription ?: @""];
  [a runModal];
}

@end

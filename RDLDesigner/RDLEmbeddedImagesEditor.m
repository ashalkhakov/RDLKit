/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLEmbeddedImagesEditor.h"
#import "RDLEditingContext.h"
#import "RDLEditor.h"
#import "RDLEmbeddedImages.h"
#import "RDLItemFactory.h"
#import "RDLPane.h"

@interface RDLEmbeddedImagesEditor () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) IBOutlet NSWindow *window;
@property (nonatomic, strong) IBOutlet NSTableView *table;
@property (nonatomic, strong) IBOutlet NSButton *removeButton;
@property (nonatomic, strong) IBOutlet NSTextField *messageLabel;
@end

// A size as the Finder writes one. Written out here, as GNUstep has no
// NSByteCountFormatter to lean on.
static NSString *RDLSizeText(NSUInteger bytes) {
  static const double kRDLBytesInKilobyte = 1000;
  if (bytes < kRDLBytesInKilobyte)
    return [NSString stringWithFormat:@"%lu bytes", (unsigned long)bytes];
  double kilobytes = bytes / kRDLBytesInKilobyte;
  if (kilobytes < kRDLBytesInKilobyte)
    return [NSString stringWithFormat:@"%.1f KB", kilobytes];
  return [NSString stringWithFormat:@"%.1f MB", kilobytes / kRDLBytesInKilobyte];
}

@implementation RDLEmbeddedImagesEditor {
  RDLEditingContext *_context;
  // Copies of the report's pictures and those imported, and for each the name
  // it had in the report -- nil for one imported here.
  NSMutableArray<RDLEmbeddedImage *> *_rows;
  NSMutableArray *_originalNames;
}

+ (instancetype)editorWithContext:(RDLEditingContext *)context {
  RDLEmbeddedImagesEditor *ed = [[self alloc] init];
  ed->_context = context;
  ed->_rows = [NSMutableArray array];
  ed->_originalNames = [NSMutableArray array];
  for (RDLEmbeddedImage *image in context.report.embeddedImages) {
    RDLEmbeddedImage *copy = [[RDLEmbeddedImage alloc] init];
    copy.name = image.name;
    copy.mimeType = image.mimeType;
    copy.imageData = image.imageData;
    [ed->_rows addObject:copy];
    [ed->_originalNames addObject:image.name ?: [NSNull null]];
  }
  NSNib *nib = [[NSNib alloc] initWithNibNamed:@"RDLEmbeddedImagesEditor" bundle:[NSBundle bundleForClass:self]];
  if (![nib instantiateWithOwner:ed topLevelObjects:NULL])
    return nil;
  RDLOwnWindow(ed.window);
  [ed.messageLabel setStringValue:@""];
  [ed selectRow:[ed->_rows count] ? 0 : -1];
  return ed;
}

+ (BOOL)runWithContext:(RDLEditingContext *)context {
  RDLEmbeddedImagesEditor *ed = [self editorWithContext:context];
  if (ed == nil)
    return NO;
  [ed.window center];
  NSInteger code = [NSApp runModalForWindow:ed.window];
  [ed.window orderOut:nil];
  return code == NSModalResponseOK;
}

- (NSArray<RDLEmbeddedImage *> *)images {
  return [_rows copy];
}

- (void)selectRow:(NSInteger)row {
  [_table reloadData];
  if (row >= 0 && row < (NSInteger)[_rows count])
    [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
  else
    [_table deselectAll:nil];
  [_removeButton setEnabled:[_table selectedRow] >= 0];
}

- (void)setName:(NSString *)name atRow:(NSUInteger)row {
  if (row < [_rows count])
    _rows[row].name = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

#pragma mark - Actions

- (BOOL)importFromURL:(NSURL *)url error:(NSError **)error {
  [_window makeFirstResponder:nil];
  RDLEmbeddedImage *image = RDLEmbeddedImageFromFile(url, _rows, error);
  if (image == nil)
    return NO;
  [_rows addObject:image];
  [_originalNames addObject:[NSNull null]];
  [self selectRow:(NSInteger)[_rows count] - 1];
  return YES;
}

- (void)importImage:(id)sender {
  (void)sender;
  NSOpenPanel *panel = [NSOpenPanel openPanel];
  [panel setAllowsMultipleSelection:YES];
  [panel setCanChooseDirectories:NO];
  [panel setAllowedFileTypes:@[ @"png", @"jpg", @"jpeg", @"gif", @"bmp" ]];
  if ([panel runModal] != NSModalResponseOK)
    return;
  for (NSURL *url in [panel URLs]) {
    NSError *error = nil;
    if (![self importFromURL:url error:&error])
      [_messageLabel setStringValue:[error localizedDescription] ?: @""];
  }
}

- (void)removeImage:(id)sender {
  (void)sender;
  [_window makeFirstResponder:nil];
  NSInteger row = [_table selectedRow];
  if (row < 0 || row >= (NSInteger)[_rows count])
    return;
  [_rows removeObjectAtIndex:(NSUInteger)row];
  [_originalNames removeObjectAtIndex:(NSUInteger)row];
  [self selectRow:MIN(row, (NSInteger)[_rows count] - 1)];
}

- (BOOL)apply {
  [_window makeFirstResponder:nil];
  NSMutableSet<NSString *> *names = [NSMutableSet set];
  for (RDLEmbeddedImage *image in _rows) {
    NSString *problem = ![RDLItemFactory isValidName:image.name]
                            ? [NSString stringWithFormat:@"“%@” is not a name a report can use.", image.name ?: @""]
                        : [names containsObject:[image.name lowercaseString]]
                            ? [NSString stringWithFormat:@"Two pictures are called %@.", image.name]
                            : nil;
    if (problem != nil) {
      [_messageLabel setStringValue:problem];
      return NO;
    }
    [names addObject:[image.name lowercaseString]];
  }
  NSMutableDictionary<NSString *, NSString *> *renames = [NSMutableDictionary dictionary];
  for (NSUInteger i = 0; i < [_rows count]; i++) {
    NSString *was = [_originalNames[i] isKindOfClass:[NSString class]] ? _originalNames[i] : nil;
    if (was != nil && ![was isEqualToString:_rows[i].name])
      renames[was] = _rows[i].name;
  }
  // The same pictures under the same names is no edit at all.
  NSArray<RDLEmbeddedImage *> *current = _context.report.embeddedImages ?: @[];
  BOOL same = [current count] == [_rows count] && [renames count] == 0;
  for (NSUInteger i = 0; same && i < [_rows count]; i++)
    same = [current[i].name isEqualToString:_rows[i].name] && [current[i].imageData isEqualToData:_rows[i].imageData];
  if (!same)
    [_context.editor setEmbeddedImages:_rows renaming:renames];
  return YES;
}

- (void)accept:(id)sender {
  (void)sender;
  if (![self apply]) {
    NSBeep();
    return;
  }
  [NSApp stopModalWithCode:NSModalResponseOK];
}

- (void)cancel:(id)sender {
  (void)sender;
  [NSApp stopModalWithCode:NSModalResponseCancel];
}

#pragma mark - Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
  (void)tableView;
  return (NSInteger)[_rows count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
  (void)tableView;
  if (row < 0 || row >= (NSInteger)[_rows count])
    return @"";
  RDLEmbeddedImage *image = _rows[(NSUInteger)row];
  NSString *which = [column identifier];
  if ([which isEqualToString:@"type"])
    return image.mimeType ?: @"";
  if ([which isEqualToString:@"size"])
    return RDLSizeText([image.imageData length]);
  return image.name ?: @"";
}

- (BOOL)tableView:(NSTableView *)tableView shouldEditTableColumn:(NSTableColumn *)column row:(NSInteger)row {
  (void)tableView;
  (void)row;
  return [[column identifier] isEqualToString:@"name"];
}

- (void)tableView:(NSTableView *)tableView
    setObjectValue:(id)value
    forTableColumn:(NSTableColumn *)column
               row:(NSInteger)row {
  (void)tableView;
  if ([[column identifier] isEqualToString:@"name"] && row >= 0 && row < (NSInteger)[_rows count])
    _rows[(NSUInteger)row].name = [[value description]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
  (void)notification;
  [_removeButton setEnabled:[_table selectedRow] >= 0];
}

@end

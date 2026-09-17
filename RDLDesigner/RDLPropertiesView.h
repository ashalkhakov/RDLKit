/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import "RDLKit.h"

@class RDLEditingContext;

// Every property of what is selected, in a grid: the element's own, then its
// style's, each with the value as text and each editable where the model can
// take text back.
//
// The inspector beside it is the friendly view -- the properties worth setting,
// laid out in sections with popups and colour wells. This is the other one:
// nothing is left out and nothing is interpreted, so a property the inspector
// has no field for can still be read and set. Report Builder has both for the
// same reason.
//
// The rows come from the class itself rather than from a list written here, so
// a property added to the model appears without anything being edited.
@interface RDLPropertiesView : NSView
- (instancetype)initWithFrame:(NSRect)frame context:(RDLEditingContext *)context;
@property (nonatomic, strong) RDLEditingContext *context;
// The key paths shown, in the order the grid lists them.
@property (nonatomic, readonly, copy) NSArray<NSString *> *keyPaths;
// Reads the selection again. Called on every change to the document and on
// every change of selection.
- (void)reload;
// The value as the grid shows it, and what typing one in does -- what a check
// drives instead of clicking a cell. NO when there is no such row, or when the
// property is one the grid only shows.
- (NSString *)textForKeyPath:(NSString *)keyPath;
- (BOOL)setText:(NSString *)text forKeyPath:(NSString *)keyPath;
@end

/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import "RDLKit.h"

@class RDLEditingContext;

// The pictures a report keeps in itself: listed with their type and size,
// imported from files, renamed and removed. An image shows one by name, so a
// rename carries to the images that show it.
//
// Modal, like the other panels here. The panel works on a list of its own, so
// Cancel leaves the report as it was, and OK sets the pictures and renames
// through the editor as one undoable step.
@interface RDLEmbeddedImagesEditor : NSObject

// YES when the panel was accepted.
+ (BOOL)runWithContext:(RDLEditingContext *)context;

// Built but not shown, for checking what it does without a modal session.
+ (instancetype)editorWithContext:(RDLEditingContext *)context;

// The pictures as the panel holds them.
@property (nonatomic, readonly, copy) NSArray<RDLEmbeddedImage *> *images;

// What the panel's controls do, declared so they can be driven without one.
- (BOOL)importFromURL:(NSURL *)url error:(NSError **)error;
- (void)setName:(NSString *)name atRow:(NSUInteger)row;
- (void)selectRow:(NSInteger)row;
- (void)removeImage:(id)sender;

// What OK does. NO, changing nothing, when a name is not an RDL name or two
// pictures share one -- which the panel then says.
- (BOOL)apply;
@end

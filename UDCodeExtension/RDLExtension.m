/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLExtension.h"
#import <UDCodeKit/UDCodeDocument.h>
#import <UDCodeKit/UDLanguageMode.h>
#import "RDLEditorViewController.h"

@implementation RDLExtension

+ (NSArray<NSMenuItem *> *)editorMenuItems {
  NSNib *nib = [[NSNib alloc] initWithNibNamed:@"RDLEditorMenus"
                                        bundle:[NSBundle bundleForClass:[RDLExtension class]]];
  NSArray *objects = nil;
  // An owner the XIB has no use for: gnustep-gui's NSNib takes no nil one.
  if (![nib instantiateWithOwner:[[NSObject alloc] init] topLevelObjects:&objects])
    return @[];
  for (id object in objects) {
    if ([object isKindOfClass:[NSMenu class]]) {
      NSArray *items = [[(NSMenu *)object itemArray] copy];
      [(NSMenu *)object removeAllItems];
      return items;
    }
  }
  return @[];
}

- (void)extensionDidLoad:(NSBundle *)bundle {
  (void)bundle;
}

- (void)extensionWillUnload:(NSBundle *)bundle {
  (void)bundle;
}

// The mode's grammar is the XML mode's (LanguageInfo.plist's grammarOf).
- (const void *)languageFuncForIdentifier:(NSString *)identifier {
  (void)identifier;
  return NULL;
}

- (NSViewController *)workbench:(id<UDWorkbench>)workbench
              editorForDocument:(UDCodeDocument *)document {
  if (![document.languageMode.identifier isEqualToString:@"rdl"])
    return nil;
  return [[RDLEditorViewController alloc] initWithDocument:document workbench:workbench];
}

// The designer's menus: their items go to the first responder, which in an
// RDL tab is its designer or its canvas; elsewhere nothing takes them, and
// they are dimmed.
- (NSArray<NSMenuItem *> *)editorMenuItemsForWorkbench:(id<UDWorkbench>)workbench {
  (void)workbench;
  return [RDLExtension editorMenuItems];
}

@end

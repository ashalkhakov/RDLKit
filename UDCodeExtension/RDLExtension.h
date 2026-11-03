/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import <UDCodeKit/UDExtension.h>

// UDCode's RDL extension (docs/UDCODE.md): Report Definition Language
// reports (.rdl, .rdlc) edited in UDCode with RDLDesigner's designer
// (RDLKitUI), in a tab of their own, as part of a project. A report is its
// document's text: the designer writes each change into it
// (RDLEditorViewController), so undo, saving, the tab's dot and source control
// are UDCode's, and a tab of its text shows it as XML (its grammar is the XML
// mode's). The designer's menus (Report, Arrange, Canvas) are in UDCode's
// Editor menu.
@interface RDLExtension : NSObject <UDExtension>
// The Editor menu's items, from RDLEditorMenus.xib.
+ (NSArray<NSMenuItem *> *)editorMenuItems;
@end

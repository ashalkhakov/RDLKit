// RDLInspectorFields — one declaration per inspector field, instead of two.
//
// The inspector held the same property table twice, written in opposite
// directions: -reload read thirty-odd model values into controls, and -changed:
// was a thirty-branch `sender == _someField` chain writing them back. Adding a
// field meant editing both, and keeping them in step was manual.
//
// A binding says where a control's value lives and how to convert it, and the
// same declaration drives both directions.
#import <AppKit/AppKit.h>

@class RDLBand;
@class RDLEditor;
@class RDLItem;
@class RDLReport;

typedef NS_ENUM(NSInteger, RDLFieldScope) {
  RDLFieldScopeItem = 0,
  RDLFieldScopeBand,
  RDLFieldScopeReport
};

typedef NS_ENUM(NSInteger, RDLFieldKind) {
  // NSTextField holding a string. An empty field writes nil, so clearing a
  // style property removes it rather than storing "".
  RDLFieldKindText = 0,
  // NSTextField holding an inch measurement, shown to three decimals.
  RDLFieldKindNumber,
  // NSTextField holding an RDL measurement written with its unit ("10pt",
  // "0.5in"), bound to an RDLLength rather than a string.
  RDLFieldKindLength,
  // NSPopUpButton whose selected title IS the value.
  RDLFieldKindPopUpTitle,
  // NSPopUpButton whose selected index maps into `values`.
  RDLFieldKindPopUpIndex,
  // A string style property that may instead be an expression. The literal
  // lives at the bound key path and the expression beside it, under
  // `expressions` -- style.color and style.expressions.color -- and exactly one
  // of the two is set. Text beginning with "=" writes the expression and clears
  // the literal; anything else does the reverse.
  RDLFieldKindTextOrExpression,
  // NSColorWell over an RDL colour string. The well opens NSColorPanel, which
  // is the standard way to pick one; the hex field beside it stays, because a
  // report's colours are often given rather than chosen.
  RDLFieldKindColor
};

@interface RDLFieldBinding : NSObject
@property (nonatomic, strong) NSControl *control;
@property (nonatomic, copy) NSString *keyPath;
@property (nonatomic, assign) RDLFieldScope scope;
@property (nonatomic, assign) RDLFieldKind kind;
// RDLFieldKindPopUpIndex: the model value for each menu index.
@property (nonatomic, copy) NSArray *values;
// Shown when the model value is empty, so the field reads as a default rather
// than as blank. Never written back.
@property (nonatomic, copy) NSString *placeholder;
@end

@interface RDLFieldBindings : NSObject
- (void)bind:(NSControl *)control
     keyPath:(NSString *)keyPath
       scope:(RDLFieldScope)scope
        kind:(RDLFieldKind)kind;
- (void)bind:(NSControl *)control
     keyPath:(NSString *)keyPath
       scope:(RDLFieldScope)scope
        kind:(RDLFieldKind)kind
      values:(NSArray *)values
 placeholder:(NSString *)placeholder;

// Model -> UI, for whichever of the three targets each binding names. A nil
// target leaves that scope's controls alone.
- (void)fillFromItem:(RDLItem *)item band:(RDLBand *)band report:(RDLReport *)report;

// UI -> model, through the editor so it undoes. Returns NO when `control` is
// not bound, so the caller can handle the composite fields itself.
- (BOOL)applyControl:(id)control
              editor:(RDLEditor *)editor
                item:(RDLItem *)item
             bandKey:(NSString *)bandKey;
@end

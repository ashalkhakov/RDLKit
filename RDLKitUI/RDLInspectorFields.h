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

// A name as the model spells it, as words for a popup: "PercentStacked" is
// "Percent stacked".
FOUNDATION_EXPORT NSString *RDLWordsOfName(NSString *name);

// A colour well beside the field that holds the colour as RDL writes it. The
// inspector pairs the two for every colour it edits, and the panels do the
// same, so a colour is chosen the same way wherever one is edited -- a well
// that opens the standard colour panel, with the text beside it for the
// colours a report gives rather than chooses, and for the expressions the
// model lets a colour be.
//
// Shows `color` in `well`: a hex colour or a colour name as it is, and white
// for nothing at all, for Transparent and for an expression -- none of which
// is a colour a well can show, and all of which the field beside it says.
FOUNDATION_EXPORT void RDLShowColorInWell(NSColorWell *well, NSString *color);
// What a well that has just been used puts in the field beside it: the colour
// as RDL writes it.
FOUNDATION_EXPORT NSString *RDLColorChosenInWell(NSColorWell *well);

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
  // NSTextField holding a whole number, never below zero: a count, not a
  // measurement.
  RDLFieldKindInteger,
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
  // A measurement that may instead be an expression. The same pair as
  // RDLFieldKindTextOrExpression, except the literal side is an RDLLength: a
  // font size is "10pt", not the string "10pt", so the two kinds cannot share
  // an implementation without writing the wrong type into the model.
  RDLFieldKindLengthOrExpression,
  // NSTextField over an RDLValue -- a property the file lets be either a
  // constant or an expression, held as one object rather than as a pair.
  // "en-US" and "=User!Language" both go in the same box, and RDLValue is
  // what decides which of the two was written.
  RDLFieldKindValue,
  // NSColorWell over an RDL colour string. The well opens NSColorPanel, which
  // is the standard way to pick one; the hex field beside it stays, because a
  // report's colours are often given rather than chosen.
  RDLFieldKindColor,
  // A checkbox over a property of two values: `values` holds what off and on
  // mean, in that order -- Normal and Italic, say -- so the box says what the
  // property is without a list of two to choose from.
  RDLFieldKindCheck
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

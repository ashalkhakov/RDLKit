// PicaInspectorFields — one declaration per inspector field, instead of two.
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

typedef NS_ENUM(NSInteger, PicaFieldScope) {
  PicaFieldScopeItem = 0,
  PicaFieldScopeBand,
  PicaFieldScopeReport
};

typedef NS_ENUM(NSInteger, PicaFieldKind) {
  // NSTextField holding a string. An empty field writes nil, so clearing a
  // style property removes it rather than storing "".
  PicaFieldKindText = 0,
  // NSTextField holding an inch measurement, shown to three decimals.
  PicaFieldKindNumber,
  // NSPopUpButton whose selected title IS the value.
  PicaFieldKindPopUpTitle,
  // NSPopUpButton whose selected index maps into `values`.
  PicaFieldKindPopUpIndex
};

@interface PicaFieldBinding : NSObject
@property (nonatomic, strong) NSControl *control;
@property (nonatomic, copy) NSString *keyPath;
@property (nonatomic, assign) PicaFieldScope scope;
@property (nonatomic, assign) PicaFieldKind kind;
// PicaFieldKindPopUpIndex: the model value for each menu index.
@property (nonatomic, copy) NSArray *values;
// Shown when the model value is empty, so the field reads as a default rather
// than as blank. Never written back.
@property (nonatomic, copy) NSString *placeholder;
@end

@interface PicaFieldBindings : NSObject
- (void)bind:(NSControl *)control
     keyPath:(NSString *)keyPath
       scope:(PicaFieldScope)scope
        kind:(PicaFieldKind)kind;
- (void)bind:(NSControl *)control
     keyPath:(NSString *)keyPath
       scope:(PicaFieldScope)scope
        kind:(PicaFieldKind)kind
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

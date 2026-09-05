#import <AppKit/AppKit.h>

// The formatting half of the rich-text editor, with no window in sight.
//
// Everything the toolbar can do to the text is here, expressed over an
// attributed string and a range, so it can be driven headlessly by checks --
// the panel itself then has nothing in it but wiring.
//
// Only what RDL can actually store is offered. RDLRichTextCodec round-trips
// font family, size, bold, italic, underline, strikethrough, colour and
// paragraph alignment; anything else a user applied would be silently dropped
// on save, so it is not offered in the first place.

typedef NS_ENUM(NSInteger, RDLRichTextTrait) {
  RDLRichTextTraitBold,
  RDLRichTextTraitItalic,
  RDLRichTextTraitUnderline,
  RDLRichTextTraitStrikethrough,
};

// A selection spanning both bold and unbold text is neither on nor off, and a
// button showing one of those two would lie about it.
typedef NS_ENUM(NSInteger, RDLTriState) {
  RDLTriStateOff = 0,
  RDLTriStateOn,
  RDLTriStateMixed,
};

// What the toolbar should show for the current selection.
@interface RDLRichTextState : NSObject
@property (nonatomic, assign) RDLTriState bold, italic, underline, strikethrough;
@property (nonatomic, copy) NSString *fontFamily;  // nil when the run varies
@property (nonatomic, assign) CGFloat fontSize;    // 0 when the run varies
@property (nonatomic, strong) NSColor *color;      // nil when the run varies
@property (nonatomic, assign) NSTextAlignment alignment;
@property (nonatomic, assign) BOOL alignmentMixed;
@end

@interface RDLRichTextFormatter : NSObject

// What `range` of `text` currently looks like. An empty range reads from
// `typing` instead, which is how a toolbar stays right when the caret is
// sitting between characters rather than covering any.
+ (RDLRichTextState *)stateOfText:(NSAttributedString *)text
                             range:(NSRange)range
                  typingAttributes:(NSDictionary *)typing;

// Each of these edits `text` over `range` and returns the typing attributes
// that should replace `typing`. With an empty range nothing is edited and only
// the returned attributes matter -- so turning bold on with no selection
// affects what gets typed next, exactly as a text editor should.
+ (NSDictionary *)setTrait:(RDLRichTextTrait)trait
                        on:(BOOL)on
                    inText:(NSMutableAttributedString *)text
                     range:(NSRange)range
          typingAttributes:(NSDictionary *)typing;

+ (NSDictionary *)setFontFamily:(NSString *)family
                         inText:(NSMutableAttributedString *)text
                          range:(NSRange)range
               typingAttributes:(NSDictionary *)typing;

+ (NSDictionary *)setFontSize:(CGFloat)size
                       inText:(NSMutableAttributedString *)text
                        range:(NSRange)range
             typingAttributes:(NSDictionary *)typing;

+ (NSDictionary *)setColor:(NSColor *)color
                    inText:(NSMutableAttributedString *)text
                     range:(NSRange)range
          typingAttributes:(NSDictionary *)typing;

// Alignment is a paragraph property, so it applies to every paragraph the
// range touches rather than to the range itself, and there is no typing-
// attribute equivalent for an empty selection sitting in a paragraph.
+ (NSDictionary *)setAlignment:(NSTextAlignment)alignment
                        inText:(NSMutableAttributedString *)text
                         range:(NSRange)range
              typingAttributes:(NSDictionary *)typing;

// The paragraphs `range` touches in full, which is what an alignment change
// has to cover.
+ (NSRange)paragraphRangeIn:(NSAttributedString *)text forRange:(NSRange)range;

// The sizes the size popup offers.
+ (NSArray<NSNumber *> *)standardFontSizes;
@end

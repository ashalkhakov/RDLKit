#import <Foundation/Foundation.h>
#import "RDLNumber.h"
@class RDLReport;
@class RDLDataSet;
@class RDLParameterValues;
@class RDLDataBinder;

// One value out of one row of a dataset.
//
// A row may be an NSDictionary, or any object that answers to key-value
// coding — so a host application can hand over the model objects it already
// has rather than converting them into dictionaries first. Dictionary keys are
// matched case-insensitively, the way RDL matches field names; a KVC object is
// asked only for keys it actually has, so a field it lacks reads as nil rather
// than raising.
FOUNDATION_EXPORT id RDLRowValue(id row, NSString *key);

// Style.Calendar: the calendar a date is written in. Default, and a style that
// names none, is the culture's own.
typedef NS_ENUM(NSInteger, RDLCalendar) {
  RDLCalendarUnspecified = 0,
  RDLCalendarDefault,
  RDLCalendarGregorian,
  RDLCalendarGregorianArabic,
  RDLCalendarGregorianMiddleEastFrench,
  RDLCalendarGregorianTransliteratedEnglish,
  RDLCalendarGregorianTransliteratedFrench,
  RDLCalendarGregorianUSEnglish,
  RDLCalendarHebrew,
  RDLCalendarHijri,
  RDLCalendarJapanese,
  RDLCalendarKorean,
  RDLCalendarTaiwan,
  RDLCalendarThaiBuddhist,
};

// What a report is being rendered as, for Globals!RenderFormat: a PDF, an HTML
// page, or the designer's preview, which is what SSRS's own viewer renders as
// RPL. Unspecified is taken as the preview.
typedef NS_ENUM(NSInteger, RDLRenderFormat) {
  RDLRenderFormatUnspecified = 0,
  RDLRenderFormatPDF,
  RDLRenderFormatHTML,
  RDLRenderFormatPreview,
};

@interface RDLEvalScope : NSObject
@property (nonatomic, strong) RDLReport *report;
@property (nonatomic, strong) id row;
@property (nonatomic, strong) RDLDataSet *dataSet;
@property (nonatomic, copy) NSArray *groupRows;
// The rows of every group instance enclosing what is being evaluated, by the
// group's name -- row groups and, in a crosstab cell, column groups. What
// Sum(x, "ColumnGroup") sums over. groupRows is the innermost of them; with
// only that, a group named in an aggregate fell back to the innermost scope and
// a matrix cell's column total came out as the cell itself.
@property (nonatomic, copy) NSDictionary<NSString *, NSArray *> *groupRowsByName;
// The rows a data region nested in the tablix cell being laid out reads: that
// cell's own instance -- a detail row, a group's rows, and in a crosstab only
// those of the cell's column as well. nil outside a tablix cell, where a data
// region reads its whole dataset.
@property (nonatomic, copy) NSArray *nestedRegionRows;
// What each textbox placed so far evaluated to, by name: what
// ReportItems!Name.Value reads. The layout fills it as it places items, and
// places the page header and footer after the body so they can see it.
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *reportItemValues;
// What each HideDuplicates text box last showed, and in which instance of its
// scope, while one tablix is placed on one page: [text, that instance's rows].
// nil outside a tablix, where there is nothing above a text box to repeat.
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSArray *> *shownDuplicates;
// The values of the Variables in scope, by name: the report's, and within a
// group, that group instance's and those of the groups around it.
@property (nonatomic, copy) NSDictionary<NSString *, id> *variableValues;
@property (nonatomic, strong) id previousRow;
// Which row this is within the innermost scope, counting from 1. What
// RowNumber() reports; 0 means the layout engine has not said.
@property (nonatomic, assign) NSInteger rowNumber;
// Which detail row this is within the whole data region, counting from 1, in
// the order the rows are shown: what RowNumber of the region's dataset reports.
// 0 where the layout engine has not said.
@property (nonatomic, assign) NSInteger regionRowNumber;
// The scopes enclosing whatever is being evaluated, outermost first: the
// dataset name, then each group's name. InScope() asks whether a name is in
// here, and Level() is a position within it.
@property (nonatomic, copy) NSArray<NSString *> *activeScopes;
// Depth within a recursive hierarchy (Group/Parent), 0 at the top. -1 when not
// in one, which is what Level() distinguishes on.
@property (nonatomic, assign) NSInteger recursionLevel;
// The rows of this node and all of its descendants, which is what a Recursive
// aggregate sums over. nil outside a recursive hierarchy.
@property (nonatomic, copy) NSArray *recursiveRows;
@property (nonatomic, assign) NSInteger pageNumber;
@property (nonatomic, assign) NSInteger totalPages;
@property (nonatomic, assign) NSInteger overallPageNumber; // 0 = same as pageNumber
@property (nonatomic, assign) NSInteger overallTotalPages; // 0 = same as totalPages
@property (nonatomic, copy) NSString *pageName; // Globals!PageName
@property (nonatomic, strong) NSDate *executionTime;
@property (nonatomic, copy) NSDictionary<NSString *, id> *paramValues; // NSString or NSArray (MultiValue)
// The report's parameters worked out from paramValues -- their values in their
// types, defaults, labels and valid values -- which Parameters! reads. Worked out
// when first read if nobody has set it; setting paramValues sets it aside.
@property (nonatomic, strong) RDLParameterValues *parameterValues;
// Who is running the report, for User!UserID; the account this process runs
// as when nil.
@property (nonatomic, copy) NSString *userID;
// Where an external image is read from, and whether a remote one may be; nil
// reads only an absolute path.
@property (nonatomic, strong) RDLDataBinder *documentBinder;
@property (nonatomic, assign) RDLRenderFormat renderFormat;
// The culture whatever is being rendered right now is written in: the
// report's Language, or an item's own override of it. Format() and every
// formatted value read this.
@property (nonatomic, copy) NSString *language;
// The culture of whoever is reading the report, which is what User!Language
// answers -- and what a report following its reader sets Language to. The
// machine's own when nothing says otherwise.
@property (nonatomic, copy) NSString *userLanguage;
// Inside the report's code: the running function's local variables, by
// lower-cased name, Nothing kept as NSNull; nil anywhere else. A name in an
// expression there is one of these, or one of the module's own variables,
// before it is anything else.
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *codeLocals;
@end

// A value's VB numeric type: an RDLNumber's own, and for a Foundation number
// handed in from outside, the type RDLNumber would read it as.
FOUNDATION_EXPORT RDLNumericType RDLNumericTypeOfValue(id value);

// A value as VB's conversion function to that type converts it, or an
// RDLExprError where that function would throw.
FOUNDATION_EXPORT id RDLValueConvertedTo(id value, RDLConversionTarget target);
// A value as VB's CBool reads it -- Nothing False, a number True unless zero,
// text True or False or a number -- or an RDLExprError where CBool would throw.
// What a condition is taken as, in an expression and in the report's code.
FOUNDATION_EXPORT id RDLValueConvertedToBoolean(id value);
// VB's Like: ? * # [list] [!list] and ranges, case-sensitive as expressions
// compare, or ignoring case as a dataset's filters do by default. NO for a
// pattern VB refuses.
FOUNDATION_EXPORT BOOL RDLTextMatchesLikePattern(NSString *text, NSString *pattern, BOOL ignoringCase);

// What an expression comes to when evaluating it fails the way VB throws -- an
// overflow, a division by zero, text used as a number that is not one. It
// reads as #Error, as SSRS shows such a value, and any operator or function
// given one gives it back.
@interface RDLExprError : NSObject
+ (instancetype)errorWithMessage:(NSString *)message;
@property (nonatomic, readonly, copy) NSString *message;
@end

// A value as the expression language reads one: as a number (text such as
// "1,000" counts; anything that is not a number is 0), as text, and as True or
// False. What the report's code converts its As types with.
FOUNDATION_EXPORT double RDLValueAsNumber(id value);
FOUNDATION_EXPORT NSString *RDLValueAsText(id value);
FOUNDATION_EXPORT BOOL RDLValueAsBoolean(id value);

// What a node of a parsed expression is. An enum rather than a string,
// because a mistyped comparison against a string is a branch that silently
// never runs.
typedef NS_ENUM(NSInteger, RDLExprNodeKind) {
  RDLExprNodeKindLiteral = 0, // `value`
  RDLExprNodeKindField,       // Fields!Name.Property -- `name`, `prop`
  RDLExprNodeKindParameter,   // Parameters!Name.Property
  RDLExprNodeKindGlobal,      // Globals!Name
  RDLExprNodeKindUser,        // User!Name
  RDLExprNodeKindReportItem,  // ReportItems!Name.Value -- another textbox's value
  RDLExprNodeKindVariable,    // Variables!Name.Value -- a report or group variable
  RDLExprNodeKindIdentifier,  // a bare name -- `name`
  RDLExprNodeKindOperator,    // `op`, `args`
  RDLExprNodeKindCall,        // a function -- `name`, `args`
  // A shared member by its dotted name -- Math.Sqrt(...), String.Format(...),
  // Code.Fn(...), Instance.Method(...) -- `name` the whole name, `args` its
  // arguments. The .NET and Visual Basic runtime members SSRS offers every
  // expression are evaluated; the report's own code is not yet.
  RDLExprNodeKindMember,
  // A member read from a value -- Fields!When.Value.Year,
  // Fields!Name.Value.Substring(0, 3) -- `name` the member, `args[0]` the
  // value it is read from and the rest its arguments.
  RDLExprNodeKindMethod,
};

typedef NS_ENUM(NSInteger, RDLExprOperator) {
  RDLExprOperatorNone = 0,
  // Arithmetic
  RDLExprOperatorAdd,
  RDLExprOperatorSubtract,
  RDLExprOperatorMultiply,
  RDLExprOperatorDivide,
  RDLExprOperatorIntegerDivide, // the backslash operator
  RDLExprOperatorModulo,        // Mod, and the % some writers use
  RDLExprOperatorPower,         // ^
  RDLExprOperatorNegate,        // unary -
  // Text
  RDLExprOperatorConcat, // &
  // Comparison
  RDLExprOperatorEqual,
  RDLExprOperatorNotEqual,
  RDLExprOperatorLess,
  RDLExprOperatorGreater,
  RDLExprOperatorLessOrEqual,
  RDLExprOperatorGreaterOrEqual,
  RDLExprOperatorLike,
  RDLExprOperatorIs,
  RDLExprOperatorIsNot,
  // Logic
  RDLExprOperatorAnd,
  RDLExprOperatorOr,
  RDLExprOperatorXor,
  RDLExprOperatorNot,
  RDLExprOperatorAndAlso,
  RDLExprOperatorOrElse,
};

// As it is written in an expression, for diagnostics.
FOUNDATION_EXPORT NSString *RDLStringFromExprOperator(RDLExprOperator op);

// One node of a parsed expression. Published so tools can walk a report's
// expressions without running them -- RDLChecker resolves names and infers
// types over exactly this tree.
@interface RDLExprNode : NSObject
@property (nonatomic, assign) RDLExprNodeKind kind;
@property (nonatomic, assign) RDLExprOperator op;
@property (nonatomic, strong) id value;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *prop;
@property (nonatomic, strong) NSMutableArray<RDLExprNode *> *args;
@end

// What a run of an expression's source is, for an editor that colours it. An
// enumeration rather than the lexer's own kind strings: those are internal and
// a mistyped comparison against one is a branch that never runs.
typedef NS_ENUM(NSInteger, RDLExprTokenKind) {
  RDLExprTokenKindUnspecified = 0,
  // Whitespace and comments between tokens.
  RDLExprTokenKindTrivia,
  RDLExprTokenKindNumber,
  RDLExprTokenKindString,
  // A name the evaluator implements, as listed by RDLExpressionCatalog.
  RDLExprTokenKindFunction,
  // Fields!, Parameters!, Globals!, ReportItems! and the name after it.
  RDLExprTokenKindReference,
  // Any other name.
  RDLExprTokenKindIdentifier,
  RDLExprTokenKindOperator,
  RDLExprTokenKindPunctuation,
  // A lexeme the lexer could not make sense of.
  RDLExprTokenKindInvalid,
  // The end of a line. Visual Basic is written in lines -- a statement ends
  // where its line does -- so the Code element's parser needs to see them. An
  // expression is one line by construction and never meets one.
  RDLExprTokenKindNewline
};

// One lexeme of an expression's source, with where it sits in it. Trivia is a
// token here too, so the tokens of a source tile it exactly -- an editor can
// walk them and account for every character without consulting the source.
@interface RDLExprToken : NSObject
@property (nonatomic, assign) NSRange range;
@property (nonatomic, assign) RDLExprTokenKind kind;
@property (nonatomic, copy) NSString *text;
// Which line of the source it was written on, counting from 1. Always 1 for an
// expression, which is one line; the Code element's tokens say where they are.
@property (nonatomic, assign) NSUInteger line;
@end

// A value as a date, or nil when it is not one. The one place text becomes a
// date in this kit: the formats are fixed and read in the POSIX locale, so a
// report means the same thing on every machine -- "2026-09-07" is the seventh
// of September wherever it is opened, which "07.09.2026" is not.
//
// Accepted: yyyy-MM-dd, yyyy-MM-dd'T'HH:mm:ss, yyyy-MM-dd HH:mm:ss,
// MM/dd/yyyy, d MMM yyyy, MMM d, yyyy. ISO first, so an unambiguous form wins
// before the American one is tried.
FOUNDATION_EXPORT NSDate *RDLDateFromValue(id value);

// One parsed RDL expression, kept losslessly.
//
// The tree is the only representation: every token carries the exact lexeme it
// was written as plus the whitespace and comments in front of it, so -source
// reproduces the input byte for byte rather than re-printing a normalised form.
// That matters because these come out of a user's .rdl file and go back into
// it: re-printing would quietly rewrite their spacing, parentheses and casing
// every time the report was saved.
@interface RDLExpr : NSObject
// nil when `source` is not an expression, i.e. does not begin with "=".
+ (instancetype)expressionWithSource:(NSString *)source;
+ (BOOL)isExpressionSource:(NSString *)source;
// Byte-for-byte the text this was parsed from, rebuilt from the tree.
@property (nonatomic, readonly, copy) NSString *source;
- (id)evaluateInScope:(RDLEvalScope *)scope;
- (NSString *)evaluateTextInScope:(RDLEvalScope *)scope;
// The parsed tree, or nil when the source did not parse. Read-only: the tokens
// remain the record of what was written.
@property (nonatomic, readonly, strong) RDLExprNode *root;
// NO when the parser stopped before the end of the expression -- it keeps what
// it understood, so the tree is a prefix of what was written and evaluating it
// silently does less than the author asked. RDLChecker reports these.
@property (nonatomic, readonly) BOOL parsedCompletely;
// The source split into runs to colour, covering it end to end including the
// whitespace, so an editor can attribute the whole string in one pass. Works on
// any text, expression or not: a source without a leading "=" is one run of
// trivia, which is what an editor showing a literal wants.
// The source, tiled into tokens. What a token means is as far as this goes:
// deciding what a token should look like belongs to whoever is drawing it, and
// RDLKit does not know about colours.
+ (NSArray<RDLExprToken *> *)tokensForSource:(NSString *)source;
// The same, for a Code element: no leading "=", and the line breaks Visual
// Basic is written in are tokens of their own.
+ (NSArray<RDLExprToken *> *)codeTokensForSource:(NSString *)source;
@end

// An RDL property that is either a literal or an expression that produces one.
// MS-RDL writes both in the same element and tells them apart by a leading "=",
// so this keeps them apart once, at parse time, and nothing downstream has to
// go looking for that "=" again.
//
// The style properties use a different shape (RDLStyleExpressions) because
// their constants are typed -- an enum or a measurement -- and a string literal
// could not carry that.
@interface RDLValue : NSObject
// nil when `source` is nil or empty.
+ (instancetype)valueWithSource:(NSString *)source;
+ (instancetype)literal:(NSString *)text;
+ (instancetype)expression:(RDLExpr *)expression;
@property (nonatomic, readonly) BOOL isExpression;
@property (nonatomic, readonly, copy) NSString *literal;      // nil when it is an expression
@property (nonatomic, readonly, strong) RDLExpr *expression;  // nil when it is a literal
// What goes back into the file: the literal, or the expression's own text.
@property (nonatomic, readonly, copy) NSString *source;
- (id)evaluateInScope:(RDLEvalScope *)scope;
- (NSString *)evaluateTextInScope:(RDLEvalScope *)scope;
// "true"/"1" and anything an expression yields that reads as true.
- (BOOL)evaluateBoolInScope:(RDLEvalScope *)scope;
@end

// The locale a culture code names -- "en-US", "de_DE", nil for the machine's
// own. RDL writes these with a hyphen and NSLocale with an underscore, which
// is the whole of the difference this papers over.
// Whether a number is a boolean rather than 1 or 0. Foundation only: GNUstep
// has no CFBooleanGetTypeID, and the two runtimes disagree about which class a
// boolean is, so this asks the object instead of the runtime. Published
// because anything reading typed data -- a JSON document, an expression --
// needs the same answer.
FOUNDATION_EXPORT BOOL RDLNumberIsBoolean(id value);

FOUNDATION_EXPORT NSLocale *RDLLocaleForLanguage(NSString *language);
// This machine's own culture, as RDL writes one: "en-US". The fallback for a
// report that names no Language, and the default for User!Language.
FOUNDATION_EXPORT NSString *RDLHostLanguage(void);
// NO for a code no locale on this machine answers to, so a report can be told
// that its Language is a typo rather than silently formatting as if it were
// English. An empty code is known: it means "the machine's own".
FOUNDATION_EXPORT BOOL RDLLanguageIsKnown(NSString *language);

// VB-style RDL expressions: tokenize → AST (translation) → execute.
// How a value is written as text: its Format, and the culture, calendar and
// digits a style writes it in. A NumeralLanguage left unset is the Language.
@interface RDLTextFormatting : NSObject
@property (nonatomic, copy) NSString *format;
@property (nonatomic, copy) NSString *language;
@property (nonatomic, assign) RDLCalendar calendar;
@property (nonatomic, copy) NSString *numeralLanguage;
// 1 to 7, as Style.NumeralVariant; 0 is unset, which is 1.
@property (nonatomic, assign) NSInteger numeralVariant;
@end

@interface RDLExpression : NSObject
+ (id)evaluate:(NSString *)expr scope:(RDLEvalScope *)scope;
+ (NSString *)evaluateText:(NSString *)expr scope:(RDLEvalScope *)scope;
+ (NSString *)formatValue:(id)value format:(NSString *)format;
+ (NSString *)formatValue:(id)value formatting:(RDLTextFormatting *)formatting;
// The same, in a culture: "de-DE" writes 1.234,50 € where "en-US" writes
// $1,234.50, and month names come out in that language. `language` nil or
// empty means the machine's own locale, which is the fallback RDL itself
// describes for a report that names no Language.
+ (NSString *)formatValue:(id)value
                   format:(NSString *)format
                 language:(NSString *)language;
/// Compact S-expression of the parsed AST. Empty if the text is not an `=` expression.
+ (NSString *)translationOf:(NSString *)expr;
@end

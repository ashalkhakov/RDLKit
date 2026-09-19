/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <Foundation/Foundation.h>
@class RDLEvalScope;

// A report's Code block, read and run.
//
// SSRS compiles Report/Code as Visual Basic. This kit runs a deliberately small
// part of that language -- the part report helper functions are written in:
//
//   Function and Sub, with ByVal and Optional parameters and As types; Dim
//   (with As and a starting value), in a function or at the top of the module,
//   where it keeps its value for the whole render; assignment, to a variable
//   or to the function's own name, and +=, -=, *=, /= and &=; If ... Then on one
//   line, and If / ElseIf / Else / End If; Select Case with values, ranges
//   (a To b) and Is comparisons; For ... To ... Step ... Next, For Each ... In
//   ... Next, While ... End While and Do [While | Until] ... Loop [While |
//   Until]; Exit Function, Sub, For, Do and While; Return; and calls to the
//   module's own functions. Comments and line continuations are allowed.
//
// Every expression inside it is an RDL expression, so Fields!, Parameters! and
// every function and .NET member an expression can use are there too. Anything
// else -- Try, With, classes, ByRef, arrays with bounds -- is one of `problems`,
// and the statement it is in is skipped when the function runs.
@interface RDLCodeModule : NSObject
+ (instancetype)moduleWithSource:(NSString *)source;
// What could not be read, one each: "line 3: ...".
@property (nonatomic, readonly, copy) NSArray<NSString *> *problems;
- (BOOL)hasFunctionNamed:(NSString *)name;
// The functions an expression can call as Code.Name, as the module spells
// them, in order of name. A Sub gives nothing back, so it is not among them.
@property (nonatomic, readonly, copy) NSArray<NSString *> *functionNames;
// How many arguments a function of this module takes; NO when it has none of
// that name.
- (BOOL)function:(NSString *)name takesAtLeast:(NSUInteger *)minimum atMost:(NSUInteger *)maximum;
// Run one of the module's functions on these argument values. Nothing (nil)
// for a Sub, for a function the module does not have, or when calls nest
// deeper than this kit allows.
- (id)callFunctionNamed:(NSString *)name arguments:(NSArray *)arguments scope:(RDLEvalScope *)scope;
// A variable declared at the top of the module, and whether there is one of
// that name.
- (BOOL)readVariableNamed:(NSString *)name value:(id *)value scope:(RDLEvalScope *)scope;
// Back to how the module starts, every module variable at its starting value.
// Layout calls it once for each render, as SSRS makes a new instance of the
// code for each.
- (void)reset;
@end

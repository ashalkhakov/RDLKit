/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// What is left of reading a module's text by hand. The scanning that used to
// live here -- trimming, finding a word outside quotes and brackets, splitting
// a list, dropping a comment -- is the shared lexer's now, and the parser reads
// tokens. Only the words that can never begin a statement are still a list.
#import "RDLCodeInternal.h"



// Words that begin a statement this kit does not run, or that can only close
// one.
NSSet<NSString *> *RDLCodeReservedWords(void) {
  return [NSSet setWithArray:@[
    @"end", @"else", @"elseif", @"next", @"loop", @"case", @"wend", @"function", @"sub", @"try", @"catch",
    @"finally", @"with", @"throw", @"goto", @"on", @"redim", @"erase", @"class", @"module", @"using", @"synclock",
    @"raiseevent", @"addhandler", @"removehandler", @"option", @"imports", @"namespace", @"structure", @"enum",
    @"property", @"get", @"set", @"let", @"resume", @"stop", @"error", @"public", @"private", @"friend",
    @"protected", @"shared"
  ]];
}


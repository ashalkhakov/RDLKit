/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// Values as the expression language holds them.
//
// Every part of the language boxes and unboxes the same handful of ways: a
// number of a particular VB type, a boolean, Nothing, and the question of
// whether something counts as a number at all. They were ten small statics at
// the top of RDLExpression.m, used from end to end of a five thousand line
// file -- which is what made that file hard to cut into pieces. Here they are
// a unit of their own, depending on nothing but RDLNumber.
#import <Foundation/Foundation.h>
#import "RDLNumber.h"

/* RDLKit's own: exported where it is built for Windows (its GNUmakefile),
   imported everywhere else, as FOUNDATION_EXPORT. */
#ifndef RDLKIT_EXPORT
#define RDLKIT_EXPORT FOUNDATION_EXPORT
#endif

RDLKIT_EXPORT BOOL RDLIsNothing(id v);
RDLKIT_EXPORT id RDLOutOfCollection(id v);
RDLKIT_EXPORT double RDLNum(id v);
RDLKIT_EXPORT BOOL RDLNumericLikeValue(id v);
RDLKIT_EXPORT BOOL RDLNumericLike(id v);
RDLKIT_EXPORT id RDLYes(BOOL b);
RDLKIT_EXPORT RDLNumber *RDLShort(int16_t v);
RDLKIT_EXPORT RDLNumber *RDLInt(int32_t v);
RDLKIT_EXPORT RDLNumber *RDLLong(int64_t v);
RDLKIT_EXPORT RDLNumber *RDLDouble(double v);

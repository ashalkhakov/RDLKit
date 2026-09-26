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

FOUNDATION_EXPORT BOOL RDLIsNothing(id v);
FOUNDATION_EXPORT id RDLOutOfCollection(id v);
FOUNDATION_EXPORT double RDLNum(id v);
FOUNDATION_EXPORT BOOL RDLNumericLikeValue(id v);
FOUNDATION_EXPORT BOOL RDLNumericLike(id v);
FOUNDATION_EXPORT id RDLYes(BOOL b);
FOUNDATION_EXPORT RDLNumber *RDLShort(int16_t v);
FOUNDATION_EXPORT RDLNumber *RDLInt(int32_t v);
FOUNDATION_EXPORT RDLNumber *RDLLong(int64_t v);
FOUNDATION_EXPORT RDLNumber *RDLDouble(double v);

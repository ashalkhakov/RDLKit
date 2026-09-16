/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLCode.h"
#import "RDLCodeInternal.h"
#import "RDLExpression.h"

#pragma mark - The pieces


@implementation RDLCodeDeclarator
@end



@implementation RDLCodeBranch
@end

RDLCodeBranch *RDLCodeBranchOf(RDLExpr *condition, NSArray<RDLCodeStatement *> *body) {
  RDLCodeBranch *branch = [[RDLCodeBranch alloc] init];
  branch.condition = condition;
  branch.body = body ?: @[];
  return branch;
}


@implementation RDLCodeStatement
@end


@implementation RDLCodeFunction
@end


@implementation RDLCodeFrame
@end


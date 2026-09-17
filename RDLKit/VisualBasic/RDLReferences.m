/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// What a reference reads: Fields!, Parameters!, Globals! and User!, and
// another text box's value or a variable, as layout recorded them.
#import "RDLRuntimeLibrary.h"

static id RDLEvaluateField(RDLEvalScope *scope, RDLExprNode *node) {
  NSString *name = node.name;
  BOOL missing = [node.prop caseInsensitiveCompare:@"IsMissing"] == NSOrderedSame;
  if (scope.row == nil)
    return missing ? RDLYes(YES) : nil;
  // Through the node's memo: this runs once per row of the dataset, and
  // resolving the key each time costs several times the lookup. The key is
  // the field's DataField; reading the row by the field's Name found nothing
  // whenever the two differed.
  RDLField *field = [scope.dataSet fieldNamed:name];
  id v = [node valueFromRow:scope.row
                          key:([scope.dataSet rowKeyForFieldNamed:name] ?: name)];
  if (v == nil && [field isCalculated])
    v = [field.value evaluateInScope:scope];
  if (missing)
    return RDLYes(v == nil);
  // A number from the data source -- a JSON document's, a host's KVC object's --
  // as the number it is.
  if ([v isKindOfClass:[NSNumber class]] && !RDLNumberIsBoolean(v))
    v = [RDLNumber numberWithFoundationNumber:v];
  RDLNumericType carried = RDLNumericTypeUnspecified;
  RDLConversionTarget declared = RDLConversionTargetOfFieldType(field.dataType, &carried);
  BOOL typed = declared != RDLConversionTargetUnspecified || field.dataType == RDLFieldDataTypeDateTime ||
               field.dataType == RDLFieldDataTypeBoolean;
  // Nothing as a collection holds it, and a typed column's empty value as a text
  // source writes it, where a data extension would hand over DBNull. A String
  // field's "" is a string.
  if (v == [NSNull null] || (typed && [v isKindOfClass:[NSString class]] && [(NSString *)v length] == 0))
    return nil;
  // In the type the report declared, as SSRS hands a report its data: the
  // text "12" in an Integer field is the Integer 12, "2026-06-03" in a DateTime
  // one a date, and text that is neither there is #Error. Nothing stays Nothing.
  if (field.dataType == RDLFieldDataTypeDateTime && [v isKindOfClass:[NSString class]] && !RDLIsNothing(v))
    return RDLConvertToDate(v);
  if (field.dataType == RDLFieldDataTypeBoolean && !RDLIsNothing(v) && !RDLNumberIsBoolean(v))
    return RDLBooleanOperand(v);
  if (field.dataType == RDLFieldDataTypeString && !RDLIsNothing(v) && ![v isKindOfClass:[NSString class]])
    return RDLStr(v);
  if (declared == RDLConversionTargetUnspecified || RDLIsNothing(v) || RDLNumericTypeOfValue(v) == carried)
    return v;
  return RDLValueConvertedTo(v, declared);
}

// The report's parameters as this scope has them, worked out the first time
// they are read.
static RDLParameterValues *RDLParametersOfScope(RDLEvalScope *scope) {
  if (scope.parameterValues == nil && scope.report != nil) {
    RDLRenderEnvironment *environment = [[RDLRenderEnvironment alloc] init];
    environment.userLanguage = scope.userLanguage;
    environment.userID = scope.userID;
    environment.renderFormat = scope.renderFormat;
    scope.parameterValues = [[RDLParameterValues alloc] initWithReport:scope.report
                                                              supplied:scope.paramValues
                                                           environment:environment];
  }
  return scope.parameterValues;
}

// Parameters!Name: its Value, the Label its value goes under -- the valid
// value's label, or the value itself when it has none -- how many values it
// has, and whether it may have several.
static id RDLParam(RDLEvalScope *scope, NSString *name, NSString *prop) {
  RDLParameterValue *parameter = [RDLParametersOfScope(scope) valueNamed:name];
  if (parameter == nil)
    return nil;
  if ([prop caseInsensitiveCompare:@"Label"] == NSOrderedSame)
    return parameter.parameter.multiValue ? parameter.labels : RDLOutOfCollection([parameter.labels firstObject]);
  if ([prop caseInsensitiveCompare:@"Count"] == NSOrderedSame)
    return RDLInt((int)([parameter.value isKindOfClass:[NSArray class]] ? [(NSArray *)parameter.value count]
                                                                                       : (parameter.value != nil ? 1 : 0)));
  if ([prop caseInsensitiveCompare:@"IsMultiValue"] == NSOrderedSame)
    return RDLYes(parameter.parameter.multiValue);
  return parameter.value;
}

@implementation RDLRenderFormatValue

- (NSString *)description {
  return _name;
}

@end

static id RDLGlobal(RDLEvalScope *scope, NSString *name) {
  NSString *n = [name lowercaseString];
  if ([n isEqualToString:@"pagenumber"])
    return RDLInt((int32_t)scope.pageNumber);
  if ([n isEqualToString:@"overallpagenumber"])
    return RDLInt((int32_t)(scope.overallPageNumber > 0 ? scope.overallPageNumber : scope.pageNumber));
  if ([n isEqualToString:@"totalpages"])
    return RDLInt((int32_t)scope.totalPages);
  if ([n isEqualToString:@"overalltotalpages"])
    return RDLInt((int32_t)(scope.overallTotalPages > 0 ? scope.overallTotalPages : scope.totalPages));
  if ([n isEqualToString:@"reportname"])
    return scope.report.name ?: @"";
  if ([n isEqualToString:@"executiontime"])
    return scope.executionTime ?: [NSDate date];
  if ([n isEqualToString:@"pagename"])
    return scope.pageName ?: @"";
  if ([n isEqualToString:@"renderformat"]) {
    RDLRenderFormatValue *format = [[RDLRenderFormatValue alloc] init];
    format.name = scope.renderFormat == RDLRenderFormatPDF    ? @"PDF"
                  : scope.renderFormat == RDLRenderFormatHTML ? @"HTML5"
                                                              : @"RPL";
    format.interactive = scope.renderFormat != RDLRenderFormatPDF;
    return format;
  }
  // A report rendered here has no folder on a report server, and no server.
  return @"";
}

static id RDLUser(RDLEvalScope *scope, NSString *name) {
  NSString *n = [name lowercaseString];
  if ([n isEqualToString:@"userid"])
    return scope.userID.length ? scope.userID : NSUserName();
  if ([n isEqualToString:@"language"])
    return scope.userLanguage.length ? scope.userLanguage : RDLHostLanguage();
  return @"";
}

id RDLLoadReference(RDLOpcode opcode, RDLExprNode *node, RDLEvalScope *scope) {
  switch (opcode) {
  case RDLOpcodeLoadField:
    return RDLEvaluateField(scope, node);
  case RDLOpcodeLoadParameter:
    return RDLParam(scope, node.name, node.prop);
  case RDLOpcodeLoadGlobal:
    return RDLGlobal(scope, node.name);
  case RDLOpcodeLoadUser:
    return RDLUser(scope, node.name);
  // Another textbox's value, as the layout recorded it when it placed that
  // textbox.
  case RDLOpcodeLoadReportItem:
    return RDLOutOfCollection(scope.reportItemValues[node.name ?: @""]);
  // A report or group variable, as layout worked it out for this scope.
  case RDLOpcodeLoadVariable:
    return RDLOutOfCollection(scope.variableValues[node.name ?: @""]);
  default:
    return nil;
  }
}

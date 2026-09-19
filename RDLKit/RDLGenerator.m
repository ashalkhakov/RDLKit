#import "RDLGenerator.h"
#import "RDLReport.h"
#import "RDLParser.h"
#import "RDLLayoutEngine.h"

@implementation RDLGenerator

+ (BOOL)bindJSONString:(NSString *)json
             toDataSet:(NSString *)name
              inReport:(RDLReport *)report
                 error:(NSError **)error {
  if (json == nil || name == nil || report == nil) {
    if (error)
      *error = [NSError errorWithDomain:@"RDLKit" code:3 userInfo:@{
        NSLocalizedDescriptionKey : @"Need JSON, a dataset name and a report to bind"
      }];
    return NO;
  }
  NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
  if (data == nil) {
    if (error)
      *error = [NSError errorWithDomain:@"RDLKit" code:4 userInfo:@{
        NSLocalizedDescriptionKey : @"Dataset JSON is not valid UTF-8"
      }];
    return NO;
  }
  id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
  if (![obj isKindOfClass:[NSArray class]]) {
    if (error)
      *error = [NSError errorWithDomain:@"RDLKit" code:2 userInfo:@{
        NSLocalizedDescriptionKey : @"Dataset JSON must be an array of objects"
      }];
    return NO;
  }
  RDLDataSet *ds = [report dataSetNamed:name];
  if (ds == nil) {
    ds = [[RDLDataSet alloc] init];
    ds.name = name;
    ds.dataSourceName = @"Demo";
    [report.dataSets addObject:ds];
  }
  ds.rows = obj;
  // Only infer when nothing is declared: allKeys is unordered, so inferring
  // over an existing schema would silently reorder the report's columns.
  NSDictionary *first = [obj firstObject];
  if ([ds.fields count] == 0 && [first isKindOfClass:[NSDictionary class]])
    [ds setFieldNames:[first allKeys]];
  return YES;
}

+ (NSArray<RDLLaidOutPage *> *)pagesForReport:(RDLReport *)report
                                   parameters:(NSDictionary<NSString *, NSString *> *)params {
  return [self pagesForReport:report parameters:params userLanguage:nil];
}

+ (NSArray<RDLLaidOutPage *> *)pagesForReport:(RDLReport *)report
                                   parameters:(NSDictionary<NSString *, NSString *> *)params
                                 userLanguage:(NSString *)userLanguage {
  return [RDLLayoutEngine pagesForReport:report paramValues:params userLanguage:userLanguage];
}

+ (NSArray<RDLLaidOutPage *> *)pagesForReport:(RDLReport *)report
                                   parameters:(NSDictionary<NSString *, NSString *> *)params
                                  environment:(RDLRenderEnvironment *)environment {
  return [RDLLayoutEngine pagesForReport:report paramValues:params environment:environment];
}

+ (RDLRenderFormat)renderFormatForBackend:(id<RDLBackend>)backend {
  if ([backend.name caseInsensitiveCompare:@"PDF"] == NSOrderedSame)
    return RDLRenderFormatPDF;
  if ([backend.name caseInsensitiveCompare:@"HTML"] == NSOrderedSame)
    return RDLRenderFormatHTML;
  return RDLRenderFormatUnspecified;
}

+ (NSArray<id<RDLBackend>> *)backends {
  return @[ [[RDLPDFBackend alloc] init], [[RDLHTMLBackend alloc] init] ];
}

+ (id<RDLBackend>)backendNamed:(NSString *)name {
  for (id<RDLBackend> b in [self backends]) {
    if ([b.name caseInsensitiveCompare:name] == NSOrderedSame)
      return b;
  }
  return nil;
}

+ (NSData *)renderPages:(NSArray<RDLLaidOutPage *> *)pages
                  title:(NSString *)title
            usingBackend:(id<RDLBackend>)backend {
  if (backend == nil)
    backend = [self backendNamed:@"PDF"];
  return [backend renderPages:pages title:title];
}

+ (NSData *)renderReport:(RDLReport *)report
              parameters:(NSDictionary<NSString *, NSString *> *)params
             usingBackend:(id<RDLBackend>)backend {
  return [self renderReport:report parameters:params usingBackend:backend userLanguage:nil];
}

+ (NSData *)renderReport:(RDLReport *)report
              parameters:(NSDictionary<NSString *, NSString *> *)params
             usingBackend:(id<RDLBackend>)backend
            userLanguage:(NSString *)userLanguage {
  RDLRenderEnvironment *environment = [[RDLRenderEnvironment alloc] init];
  environment.userLanguage = userLanguage;
  return [self renderReport:report parameters:params usingBackend:backend environment:environment];
}

+ (NSData *)renderReport:(RDLReport *)report
              parameters:(NSDictionary<NSString *, NSString *> *)params
             usingBackend:(id<RDLBackend>)backend
             environment:(RDLRenderEnvironment *)environment {
  if (backend == nil)
    backend = [self backendNamed:@"PDF"];
  RDLRenderEnvironment *rendering = [[RDLRenderEnvironment alloc] init];
  rendering.userLanguage = environment.userLanguage;
  rendering.userID = environment.userID;
  rendering.documentBinder = environment.documentBinder;
  rendering.renderFormat = environment.renderFormat != RDLRenderFormatUnspecified ? environment.renderFormat
                                                                                  : [self renderFormatForBackend:backend];
  NSArray *pages = [self pagesForReport:report parameters:params environment:rendering];
  return [self renderPages:pages title:report.name ?: @"Report" usingBackend:backend];
}

+ (NSData *)PDFForReport:(RDLReport *)report
              parameters:(NSDictionary<NSString *, NSString *> *)params {
  return [self renderReport:report parameters:params usingBackend:[self backendNamed:@"PDF"]];
}

+ (NSString *)HTMLStringForReport:(RDLReport *)report
                       parameters:(NSDictionary<NSString *, NSString *> *)params {
  RDLRenderEnvironment *environment = [[RDLRenderEnvironment alloc] init];
  environment.renderFormat = RDLRenderFormatHTML;
  NSArray *pages = [self pagesForReport:report parameters:params environment:environment];
  return [RDLHTMLBackend HTMLStringForPages:pages title:report.name ?: @"Report"];
}

+ (NSData *)HTMLForReport:(RDLReport *)report
               parameters:(NSDictionary<NSString *, NSString *> *)params {
  return [self renderReport:report parameters:params usingBackend:[self backendNamed:@"HTML"]];
}

+ (NSData *)PDFFromXML:(NSString *)xml
            parameters:(NSDictionary<NSString *, NSString *> *)params
                 error:(NSError **)error {
  RDLReport *report = [RDLParser reportFromXMLString:xml error:error];
  if (report == nil)
    return nil;
  return [self PDFForReport:report parameters:params];
}

+ (NSString *)HTMLFromXML:(NSString *)xml
               parameters:(NSDictionary<NSString *, NSString *> *)params
                    error:(NSError **)error {
  RDLReport *report = [RDLParser reportFromXMLString:xml error:error];
  if (report == nil)
    return nil;
  return [self HTMLStringForReport:report parameters:params];
}

@end

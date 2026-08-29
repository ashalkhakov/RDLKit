#import "RDLGenerator.h"
#import "RDLReport.h"
#import "RDLParser.h"
#import "RDLLayoutEngine.h"

@implementation RDLGenerator

+ (void)bindJSONString:(NSString *)json
             toDataSet:(NSString *)name
              inReport:(RDLReport *)report
                 error:(NSError **)error {
  if (json == nil || name == nil || report == nil)
    return;
  NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
  if (data == nil)
    return;
  id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
  if (![obj isKindOfClass:[NSArray class]]) {
    if (error)
      *error = [NSError errorWithDomain:@"PicaKit" code:2 userInfo:@{
        NSLocalizedDescriptionKey : @"Dataset JSON must be an array of objects"
      }];
    return;
  }
  RDLDataSet *ds = nil;
  for (RDLDataSet *d in report.dataSets) {
    if ([d.name isEqualToString:name]) {
      ds = d;
      break;
    }
  }
  if (ds == nil) {
    ds = [[RDLDataSet alloc] init];
    ds.name = name;
    ds.dataSourceName = @"Demo";
    [report.dataSets addObject:ds];
  }
  ds.rows = obj;
  NSDictionary *first = [obj firstObject];
  if ([first isKindOfClass:[NSDictionary class]])
    ds.fields = [first allKeys];
}

+ (NSArray<RDLLaidOutPage *> *)pagesForReport:(RDLReport *)report
                                   parameters:(NSDictionary<NSString *, NSString *> *)params {
  return [RDLLayoutEngine pagesForReport:report paramValues:params];
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
  NSArray *pages = [self pagesForReport:report parameters:params];
  return [self renderPages:pages title:report.name ?: @"Report" usingBackend:backend];
}

+ (NSData *)PDFForReport:(RDLReport *)report
              parameters:(NSDictionary<NSString *, NSString *> *)params {
  return [self renderReport:report parameters:params usingBackend:[self backendNamed:@"PDF"]];
}

+ (NSString *)HTMLStringForReport:(RDLReport *)report
                       parameters:(NSDictionary<NSString *, NSString *> *)params {
  NSArray *pages = [self pagesForReport:report parameters:params];
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

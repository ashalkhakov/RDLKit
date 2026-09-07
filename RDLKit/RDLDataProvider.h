/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <Foundation/Foundation.h>
#import "RDLReport.h"
#import "RDLJSONPath.h"

// Where a dataset's rows come from -- documents, always. This kit is a local
// report viewer: the data is a file the host already has, content embedded in
// the report, or rows handed over in code. Shared data source references and
// database providers are deliberately not here; they belong to a report server,
// which is a different program.
//
// RDL says where in two places: the data
// source's DataProvider and ConnectString say what and where, and the dataset's
// Query/CommandText says which part of it to take -- a JSONPath, an XPath, or
// nothing at all for a flat file.
//
//   <DataSource Name="Films">
//     <ConnectionProperties>
//       <DataProvider>JSON</DataProvider>
//       <ConnectString>jsondoc=films.json</ConnectString>
//     </ConnectionProperties>
//   </DataSource>
//   <DataSet Name="Movies">
//     <Query><DataSourceName>Films</DataSourceName>
//            <CommandText>$.Movie[*]</CommandText></Query>
//   </DataSet>

typedef NS_ENUM(NSInteger, RDLDataProviderKind) {
  RDLDataProviderKindUnspecified = 0,
  RDLDataProviderKindJSON,
  RDLDataProviderKindXML,
  RDLDataProviderKindCSV,
};

FOUNDATION_EXPORT RDLDataProviderKind RDLDataProviderKindFromString(NSString *name);
// "JSON" / "XML" / "CSV", as a DataProvider element is written.
FOUNDATION_EXPORT NSString *RDLStringFromDataProviderKind(RDLDataProviderKind kind);

// A connection string, read into its parts: "jsondoc=films.json" is
// {"jsondoc": "films.json"}, and "data.csv;HasHeaders=true" is
// {"": "data.csv", "hasheaders": "true"} -- a bare first token is the document,
// which is how the CSV provider's strings are written. Keys are lower-cased,
// because RDL's own are written every which way.
FOUNDATION_EXPORT NSDictionary<NSString *, NSString *> *RDLConnectionProperties(NSString *connectString);
// The inverse: the properties written back as a connect string. The document
// comes first and the options follow in a stable order, so editing a source in
// the designer does not rewrite the whole line every time.
FOUNDATION_EXPORT NSString *RDLConnectionString(NSDictionary<NSString *, NSString *> *properties);
// Which key names the document for a kind of provider: a file to read
// ("jsondoc", "xmldoc", or the bare document for CSV), or content carried in
// the report ("jsondata", "xmldata", "data"). An editor asks for these rather
// than knowing the vocabulary.
FOUNDATION_EXPORT NSString *RDLDocumentKeyForProviderKind(RDLDataProviderKind kind);
FOUNDATION_EXPORT NSString *RDLInlineKeyForProviderKind(RDLDataProviderKind kind);

#pragma mark - Providers

@protocol RDLDataProvider <NSObject>
// Matched against the data source's DataProvider, case-insensitively.
@property (nonatomic, readonly, copy) NSString *name;
// The rows of one dataset: an array of dictionaries, which is the shape
// RDLDataSet.rows takes everywhere else in the kit. nil (with `error` set) when
// the data could not be read; an empty array when it could and there are none.
//
// `documentData` is what the connect string pointed at, already loaded --
// providers do no I/O of their own, so a caller decides what may be opened.
- (NSArray *)rowsFromData:(NSData *)documentData
                 dataSet:(RDLDataSet *)dataSet
              properties:(NSDictionary<NSString *, NSString *> *)properties
                   error:(NSError **)error;
@end

// JSON, via JSONPath. Objects become rows; a selected array is flattened one
// level, so "$.Movie" and "$.Movie[*]" both give the films rather than one row
// holding all of them. Values that are themselves objects or arrays stay in the
// row: that is what a nested data region reads.
@interface RDLJSONDataProvider : NSObject <RDLDataProvider>
@end

// XML, via XPath. Each selected element is a row: its attributes and its leaf
// children are fields, and a child with children of its own stays as rows of
// its own, for a nested region to bind to.
@interface RDLXMLDataProvider : NSObject <RDLDataProvider>
@end

// Delimited or fixed-width text. Options ride in the connect string:
//
//   data.csv;HasHeaders=true;Delimiter=Tab
//   data.txt;Widths=10,20,8;HasHeaders=false
//
// Without headers the fields are Column1, Column2 … , which is also what the
// designer shows. CSV is flat: there is nothing here for a nested region.
@interface RDLCSVDataProvider : NSObject <RDLDataProvider>
@end

#pragma mark - Binding

// Fills a report's datasets from what its data sources point at. One binder
// per bind: it holds where relative paths are resolved from and what it is
// allowed to open, so two of them may run at once with different answers.
@interface RDLDataBinder : NSObject
// Relative documents ("jsondoc=films.json") resolve against this -- the
// report's own file, normally. nil resolves against the working directory.
- (instancetype)initWithBaseURL:(NSURL *)baseURL;
@property (nonatomic, readonly, copy) NSURL *baseURL;
// The providers to match a data source against; the three built-in ones unless
// replaced. A host may add its own.
@property (nonatomic, copy) NSArray<id<RDLDataProvider>> *providers;
// NO by default, and deliberately: a report is a document that may arrive from
// anywhere, and "jsondoc=https://…" in one would otherwise fetch as soon as it
// was opened. A host that wants that says so.
@property (nonatomic, assign) BOOL allowsRemoteDocuments;
// What was skipped and why -- a data source naming a provider nobody
// implements, a document that could not be read. Binding a report is
// best-effort: one unreadable dataset should not stop the others.
@property (nonatomic, readonly, copy) NSArray<NSString *> *notes;

// Every dataset whose data source names a provider this binder has. Datasets
// bound another way (rows set in code, JSON in CommandText) are left alone.
// Returns NO only when nothing could be bound at all.
- (BOOL)bindReport:(RDLReport *)report error:(NSError **)error;
- (BOOL)bindDataSet:(RDLDataSet *)dataSet inReport:(RDLReport *)report error:(NSError **)error;
@end

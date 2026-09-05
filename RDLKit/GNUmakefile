include $(GNUSTEP_MAKEFILES)/common.make

LIBRARY_NAME = RDLKit
RDLKit_NEEDS_GUI = yes
RDLKit_LIBRARIES_DEPEND_UPON += -lz -ldispatch
RDLKit_OBJCFLAGS += -fobjc-arc -Wall
RDLKit_HEADER_FILES = \
  RDLKit.h \
  RDLCompatibility.h \
  RDLReport.h \
  RDLParser.h \
  RDLExpression.h \
  RDLLayoutEngine.h \
  RDLView.h \
  RDLBackend.h \
  RDLGenerator.h \
  RDLTextAttributes.h
RDLKit_OBJC_FILES = \
  RDLReport.m \
  RDLParser.m \
  RDLUpgrader.m \
  RDLChartRenderer.m \
  RDLChecker.m \
  RDLZipArchive.m \
  RDLDocxReader.m \
  RDLImporter.m \
  RDLExpression.m \
  RDLExpressionCatalog.m \
  RDLLayoutEngine.m \
  RDLView.m \
  RDLHTMLBackend.m \
  RDLPDFBackend.m \
  RDLGenerator.m \
  RDLTextAttributes.m

include $(GNUSTEP_MAKEFILES)/library.make

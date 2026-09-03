include $(GNUSTEP_MAKEFILES)/common.make

LIBRARY_NAME = PicaKit
PicaKit_NEEDS_GUI = yes
PicaKit_OBJCFLAGS += -fobjc-arc -Wall
PicaKit_HEADER_FILES = \
  PicaKit.h \
  PicaCompatibility.h \
  RDLReport.h \
  RDLParser.h \
  RDLExpression.h \
  RDLLayoutEngine.h \
  RDLView.h \
  RDLBackend.h \
  RDLGenerator.h \
  RDLTextAttributes.h
PicaKit_OBJC_FILES = \
  RDLReport.m \
  RDLParser.m \
  RDLUpgrader.m \
  RDLChartRenderer.m \
  RDLExpression.m \
  RDLLayoutEngine.m \
  RDLView.m \
  RDLHTMLBackend.m \
  RDLPDFBackend.m \
  RDLGenerator.m \
  RDLTextAttributes.m

include $(GNUSTEP_MAKEFILES)/library.make

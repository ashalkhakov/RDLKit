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
  RDLChange.h \
  RDLSelection.h \
  RDLDocument.h \
  RDLEditor.h \
  RDLItemFactory.h
PicaKit_OBJC_FILES = \
  RDLReport.m \
  RDLParser.m \
  RDLExpression.m \
  RDLLayoutEngine.m \
  RDLView.m \
  RDLHTMLBackend.m \
  RDLPDFBackend.m \
  RDLGenerator.m \
  RDLChange.m \
  RDLSelection.m \
  RDLDocument.m \
  RDLEditor.m \
  RDLItemFactory.m

include $(GNUSTEP_MAKEFILES)/library.make

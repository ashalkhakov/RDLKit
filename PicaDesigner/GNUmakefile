include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = Pica
Pica_NEEDS_GUI = yes
Pica_OBJCFLAGS += -fobjc-arc -Wall -I../PicaKit
Pica_OBJC_FILES = \
  main.m \
  PicaEditingContext.m \
  PicaChange.m \
  PicaSelection.m \
  PicaDocument.m \
  PicaEditor.m \
  PicaItemFactory.m \
  PicaPageGeometry.m \
  PicaRichTextCodec.m \
  PicaRichTextFormatter.m \
  PicaCanvasView.m \
  PicaCanvasRenderer.m \
  PicaInPlaceEditor.m \
  PicaCanvasInteraction.m \
  PicaDesignerWindow.m \
  PicaOutlineDataSource.m \
  PicaGeneratorWindow.m \
  PicaAppDelegate.m \
  PicaSamples.m \
  PicaInspectorView.m \
  PicaInspectorFields.m \
  PicaExpressionHelper.m \
  PicaTablixEditor.m \
  PicaNewReport.m \
  PicaNewReportPanel.m \
  PicaRichTextEditor.m \
  PicaDataView.m \
  PicaWelcomeWindow.m
# PicaKit is built in the tree beside this one and not installed, so the
# linker has to be told where it is. ADDITIONAL_LIB_DIRS rather than a
# per-instance variable: it is the documented form and applies whatever the
# instance type is.
ADDITIONAL_LIB_DIRS += -L../PicaKit/$(GNUSTEP_OBJ_DIR)
Pica_OBJC_LIBS += -lPicaKit -ldispatch
Pica_APPLICATION_ICON =

# The windows and the menu bar are XIBs. Xcode compiles them to .nib; here they
# are copied in as they are, and gnustep-gui reads the XIB directly (GSXib5).
# Both are found by the same -initWithNibNamed:, which is why no path or
# extension appears anywhere in the source.
Pica_RESOURCE_FILES = \
  MainMenu.xib \
  PicaWelcomeWindow.xib \
  PicaDesignerWindow.xib \
  PicaGeneratorWindow.xib \
  PicaInspectorSections.xib \
  PicaAddElementPanel.xib \
  PicaPreviewWindow.xib \
  PicaTablixEditor.xib \
  PicaRichTextEditor.xib \
  PicaNewReportPanel.xib

# Left empty on purpose: the menu bar is loaded explicitly in
# -[PicaAppDelegate loadMenuBar], so that the Samples submenu can be filled in
# from the sample catalogue through a real outlet.
Pica_MAIN_MODEL_FILE =

include $(GNUSTEP_MAKEFILES)/application.make

include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = RDLDesigner
RDLDesigner_NEEDS_GUI = yes
RDLDesigner_OBJCFLAGS += -fobjc-arc -Wall -I../RDLKit
RDLDesigner_OBJC_FILES = \
  main.m \
  RDLEditingContext.m \
  RDLChange.m \
  RDLSelection.m \
  RDLDocument.m \
  RDLEditor.m \
  RDLItemFactory.m \
  RDLPageGeometry.m \
  RDLRichTextCodec.m \
  RDLRichTextFormatter.m \
  RDLCanvasView.m \
  RDLCanvasRenderer.m \
  RDLInPlaceEditor.m \
  RDLCanvasInteraction.m \
  RDLDesignerWindow.m \
  RDLOutlineDataSource.m \
  RDLGeneratorWindow.m \
  RDLAppDelegate.m \
  RDLSamples.m \
  RDLInspectorView.m \
  RDLInspectorFields.m \
  RDLExpressionHelper.m \
  RDLTablixEditor.m \
  RDLNewReport.m \
  RDLNewReportPanel.m \
  RDLRichTextEditor.m \
  RDLDataView.m \
  RDLWelcomeWindow.m \
  RDLExpressionEditor.m \
  RDLInsertPalette.m \
  RDLExpressionField.m \
  RDLTabBadge.m \
  RDLDatasetNavigator.m \
  RDLFieldInspectorView.m \
  RDLDatasetFieldsView.m \
  ThirdParty/DMTabBar/DMTabBar.m \
  ThirdParty/DMTabBar/DMTabBarItem.m
# RDLKit is built in the tree beside this one and not installed, so the
# linker has to be told where it is. ADDITIONAL_LIB_DIRS rather than a
# per-instance variable: it is the documented form and applies whatever the
# instance type is.
ADDITIONAL_LIB_DIRS += -L../RDLKit/$(GNUSTEP_OBJ_DIR)
RDLDesigner_OBJC_LIBS += -lRDLKit -ldispatch
RDLDesigner_APPLICATION_ICON =

# The windows and the menu bar are XIBs. Xcode compiles them to .nib; here they
# are copied in as they are, and gnustep-gui reads the XIB directly (GSXib5).
# Both are found by the same -initWithNibNamed:, which is why no path or
# extension appears anywhere in the source.
RDLDesigner_RESOURCE_FILES = \
  RDLExpressionEditor.xib \
  MainMenu.xib \
  RDLWelcomeWindow.xib \
  RDLDesignerWindow.xib \
  RDLGeneratorWindow.xib \
  RDLInspectorSections.xib \
  RDLAddElementPanel.xib \
  RDLPreviewWindow.xib \
  RDLTablixEditor.xib \
  RDLRichTextEditor.xib \
  RDLNewReportPanel.xib

# Left empty on purpose: the menu bar is loaded explicitly in
# -[RDLAppDelegate loadMenuBar], so that the Samples submenu can be filled in
# from the sample catalogue through a real outlet.
RDLDesigner_MAIN_MODEL_FILE =

include $(GNUSTEP_MAKEFILES)/application.make

include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = Pica
Pica_NEEDS_GUI = yes
Pica_OBJCFLAGS += -fobjc-arc -Wall -I../PicaKit
Pica_OBJC_FILES = \
  main.m \
  PicaEditingContext.m \
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
  PicaModalSession.m \
  PicaTablixEditor.m \
  PicaRichTextEditor.m \
  PicaDataView.m \
  PicaWelcomeWindow.m
Pica_OBJC_LIBS += -lPicaKit
Pica_APPLICATION_ICON =
Pica_MAIN_MODEL_FILE =

include $(GNUSTEP_MAKEFILES)/application.make

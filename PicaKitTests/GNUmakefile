# An XCTest bundle that requires tools-xctest
# (https://github.com/gnustep/tools-xctest)
#
#   make          build the bundle
#   make run-tests  build and run it
include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = PicaKitTests

PicaKitTests_OBJC_FILES = \
  PicaKitTests.m
PicaKitTests_OBJCFLAGS += -fobjc-arc -Wall
PicaKitTests_INCLUDE_DIRS = -I../PicaKit
ADDITIONAL_LIB_DIRS += -L../PicaKit/$(GNUSTEP_OBJ_DIR)
PicaKitTests_BUNDLE_LIBS += -lPicaKit -lXCTest -ldispatch
# The PDF backend and text measurement are AppKit.
PicaKitTests_NEEDS_GUI = yes

# Heap corruption does not name itself: "malloc_consolidate(): unaligned
# fastbin chunk" is reported by whichever allocation happens to notice, long
# after the overflow. Build with SANITIZE=1 to have AddressSanitizer name the
# write and the allocation it ran past instead:
#
#   make run-tests SANITIZE=1
#
ifeq ($(SANITIZE),1)
ADDITIONAL_OBJCFLAGS += -fsanitize=address -fno-omit-frame-pointer -g
ADDITIONAL_LDFLAGS += -fsanitize=address
endif

include $(GNUSTEP_MAKEFILES)/bundle.make

XCTEST ?= xctest

# The .docx fixtures are found relative to __FILE__ rather than through the
# bundle, so they need no RESOURCE_FILES entry -- but they do mean the checks
# have to run from a source tree, not from an installed bundle.
.PHONY: run-tests
run-tests: all
	LD_LIBRARY_PATH="$(CURDIR)/../PicaKit/$(GNUSTEP_OBJ_DIR):$$LD_LIBRARY_PATH" \
	  $(XCTEST) $(BUNDLE_NAME).bundle

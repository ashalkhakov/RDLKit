# An XCTest bundle that requires tools-xctest
# (https://github.com/gnustep/tools-xctest)
#
#   make          build the bundle
#   make run-tests  build and run it
include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = RDLKitTests

RDLKitTests_OBJC_FILES = \
  RDLKitTests.m
RDLKitTests_OBJCFLAGS += -fobjc-arc -Wall
RDLKitTests_INCLUDE_DIRS = -I../RDLKit
ADDITIONAL_LIB_DIRS += -L../RDLKit/$(GNUSTEP_OBJ_DIR)
RDLKitTests_BUNDLE_LIBS += -lRDLKit -lXCTest -ldispatch
# The PDF backend and text measurement are AppKit.
RDLKitTests_NEEDS_GUI = yes

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
# The bundle is dlopened by an xctest binary that is not instrumented, so the
# ASan runtime has to be loaded first or its interceptors are never installed.
ASAN_LIB := $(shell $(CC) -print-file-name=libclang_rt.asan-x86_64.so)
# Leaks are not what is being looked for here, and a test bundle reports plenty.
# handle_abort=1 so the SIGABRT the timeout below sends is reported by ASan
# with a symbolized backtrace, instead of the process simply disappearing.
SANITIZE_ENV := LD_PRELOAD="$(ASAN_LIB)" ASAN_OPTIONS=detect_leaks=0:abort_on_error=1:handle_abort=1
endif

include $(GNUSTEP_MAKEFILES)/bundle.make

XCTEST ?= xctest

# The .docx fixtures are found relative to __FILE__ rather than through the
# bundle, so they need no RESOURCE_FILES entry -- but they do mean the checks
# have to run from a source tree, not from an installed bundle.
.PHONY: run-tests
# Bounded. A test that opens a modal panel can wait for an event that never
# arrives on a machine with no window manager, and an unbounded hang costs the
# whole job's timeout and says nothing about where it stopped. TEST_TIMEOUT
# seconds later the run is aborted, and with SANITIZE=1 that abort comes back
# as a backtrace naming the call that was waiting.
TEST_TIMEOUT ?= 600

run-tests: all
	$(SANITIZE_ENV) \
	LD_LIBRARY_PATH="$(CURDIR)/../RDLKit/$(GNUSTEP_OBJ_DIR):$$LD_LIBRARY_PATH" \
	  timeout -s ABRT $(TEST_TIMEOUT) $(XCTEST) $(BUNDLE_NAME).bundle

# An XCTest bundle that requires tools-xctest
# (https://github.com/gnustep/tools-xctest)
#
#   make          build the bundle
#   make run-tests  build and run it
include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = RDLKitTests

RDLKitTests_OBJC_FILES = \
  RDLTestSupport.m \
  RDLParserTests.m \
  RDLExpressionTests.m \
  RDLLayoutTests.m \
  RDLBackendTests.m \
  RDLImportTests.m
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
# Named after the architecture, so this cannot be hardcoded: on anything but
# x86_64 the lookup returns the name it was given, LD_PRELOAD then fails
# quietly, and the run proceeds with no interceptors and no report.
ASAN_ARCH := $(shell uname -m)
ASAN_LIB := $(shell $(CC) -print-file-name=libclang_rt.asan-$(ASAN_ARCH).so)
# Leaks are not what is being looked for here, and a test bundle reports plenty.
# handle_abort=1 so the SIGABRT the timeout below sends is reported by ASan
# with a symbolized backtrace, instead of the process simply disappearing.
SANITIZE_ENV := LD_PRELOAD="$(ASAN_LIB)" ASAN_OPTIONS=detect_leaks=0:abort_on_error=1:handle_abort=1
endif

# Undefined behaviour, which is a different question from memory safety and a
# different tool: UBSAN=1 checks signed overflow, shifts, misaligned and null
# pointers, out-of-range enum and bool loads, and float-to-integer conversions
# that do not fit. None of it touches the allocator, so unlike the sanitizers
# above it does not change the shape of the heap it is run against.
#
#   make -C RDLKit UBSAN=1 && make -C RDLKitTests run-tests UBSAN=1
ifeq ($(UBSAN),1)
ADDITIONAL_OBJCFLAGS += -fsanitize=undefined -fno-omit-frame-pointer -g
ADDITIONAL_CFLAGS += -fsanitize=undefined -fno-omit-frame-pointer -g
ADDITIONAL_LDFLAGS += -fsanitize=undefined
# As with AddressSanitizer: the bundle is dlopened by an xctest binary that is
# not instrumented, so the runtime has to be loaded first. halt_on_error=0 so
# one run reports everything it finds rather than the first thing only.
UBSAN_ARCH := $(shell uname -m)
UBSAN_LIB := $(shell $(CC) -print-file-name=libclang_rt.ubsan_standalone-$(UBSAN_ARCH).so)
SANITIZE_ENV := LD_PRELOAD="$(UBSAN_LIB)" UBSAN_OPTIONS=print_stacktrace=1:halt_on_error=0
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

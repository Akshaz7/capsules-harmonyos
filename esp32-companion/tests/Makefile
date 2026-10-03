# Host-side unit tests for the firmware's pure logic and for the mock. No ESP-IDF needed:
#
#   make -C tests test
#
# The firmware files are compiled as they are, against the stand-ins in stubs/.
# With sanitizers, where the compiler has them: make -C tests test SANITIZE=-fsanitize=address,undefined

CC ?= cc
PYTHON ?= python3
SANITIZE ?=
# -Wno-unused-parameter: ESP-IDF callbacks have parameters the firmware does not use
CFLAGS := -std=gnu11 -O1 -g -Wall -Wextra -Wno-unused-parameter -Werror $(SANITIZE)
INCLUDES := -I. -Istubs -I../main -Ivendor/cJSON

BIN := build
HEADERS := $(wildcard *.h stubs/*.h stubs/freertos/*.h ../main/*.h)
TESTS := $(BIN)/test_validate $(BIN)/test_capsule $(BIN)/test_http_api $(BIN)/test_relay

.PHONY: test clean
test: $(TESTS)
	$(BIN)/test_validate vectors/json_scan.txt vectors/labels.txt
	$(BIN)/test_capsule vectors/labels.txt
	$(BIN)/test_http_api
	$(BIN)/test_relay
	$(PYTHON) test_mock.py
	$(PYTHON) test_mock_relay.py

$(BIN)/test_validate: test_validate.c ../main/validate.c $(HEADERS)
	@mkdir -p $(BIN)
	$(CC) $(CFLAGS) $(INCLUDES) -o $@ test_validate.c ../main/validate.c

# capsule.c is #included by the test, to reach its static functions
$(BIN)/test_capsule: test_capsule.c ../main/capsule.c stubs/stubs.c $(HEADERS)
	@mkdir -p $(BIN)
	$(CC) $(CFLAGS) $(INCLUDES) -o $@ test_capsule.c stubs/stubs.c

# cJSON is third-party code: built without -Werror
$(BIN)/cJSON.o: vendor/cJSON/cJSON.c vendor/cJSON/cJSON.h
	@mkdir -p $(BIN)
	$(CC) -std=gnu11 -O1 -g $(SANITIZE) -c -o $@ vendor/cJSON/cJSON.c

$(BIN)/test_http_api: test_http_api.c ../main/http_api.c ../main/capsule_json.c ../main/capsule.c ../main/validate.c \
		stubs/stubs.c stubs/fake_httpd.c $(BIN)/cJSON.o $(HEADERS)
	@mkdir -p $(BIN)
	$(CC) $(CFLAGS) $(INCLUDES) -o $@ test_http_api.c ../main/http_api.c ../main/capsule_json.c ../main/capsule.c ../main/validate.c \
		stubs/stubs.c stubs/fake_httpd.c $(BIN)/cJSON.o -lm

RELAY_SOURCES := ../main/relay_sync.c ../main/capsule_json.c ../main/capsule.c ../main/validate.c
$(BIN)/test_relay: test_relay.c $(RELAY_SOURCES) stubs/stubs.c stubs/sha256.c $(BIN)/cJSON.o $(HEADERS)
	@mkdir -p $(BIN)
	$(CC) $(CFLAGS) $(INCLUDES) -o $@ test_relay.c $(RELAY_SOURCES) stubs/stubs.c stubs/sha256.c $(BIN)/cJSON.o -lm

clean:
	rm -rf $(BIN)

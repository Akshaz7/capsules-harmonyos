// Host tests for main/http_api.c: request validation, status codes and what a rejected
// request leaves behind. http_api.c and capsule.c are the firmware's own files, built
// against the stand-ins in tests/stubs/; cJSON is the copy in tests/vendor/.
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "capsule.h"
#include "check.h"
#include "fake_httpd.h"
#include "http_api.h"
#include "motion.h"
#include "stubs.h"
#include "ui.h"

// ---- the two things http_api.c needs from the rest of the firmware ----

static bool s_motion_sensor = true;
static int s_screen_width, s_screen_height;  // 0: no display

bool motion_available(void)
{
    return s_motion_sensor;
}

uint16_t *ui_snapshot(int *width, int *height)
{
    if (s_screen_width == 0) {
        return NULL;
    }
    uint16_t *pixels = malloc(sizeof(uint16_t) * s_screen_width * s_screen_height);
    for (int i = 0; i < s_screen_width * s_screen_height; i++) {
        pixels[i] = i == 0 ? 0xF800 : 0x07E0;  // top-left red, the rest green
    }
    *width = s_screen_width;
    *height = s_screen_height;
    return pixels;
}

// ---- helpers ----

static fake_exchange_t s_last;

static const char *post(const char *uri, const char *body)
{
    s_last = fake_request(HTTP_POST, uri, body, strlen(body), strlen(body));
    CHECK_INT(stub_lock_depth, 0);
    return s_last.req.response;
}

static const char *get_state(void)
{
    s_last = fake_request(HTTP_GET, "/state", "", 0, 0);
    return s_last.req.response;
}

#define CHECK_STATUS(wanted) CHECK_INT(s_last.status, wanted)
#define CHECK_ERROR(wanted_status, message)                                 \
    do {                                                                    \
        CHECK_INT(s_last.status, wanted_status);                            \
        CHECK_STR(s_last.req.response, "{\"error\":\"" message "\"}");      \
        CHECK_STR(s_last.req.type, "application/json");                     \
    } while (0)
#define CHECK_HAS(text) CHECK(strstr(s_last.req.response, text) != NULL)

#define TEA "{\"type\":\"timer\",\"label\":\"Tea\",\"seconds\":180,\"running\":false}"
#define TEA_STATE                                                                                        \
    "{\"type\":\"timer\",\"label\":\"Tea\",\"count\":0,\"seconds\":180,\"remaining_seconds\":180,"       \
    "\"running\":false,\"done\":false,\"motion\":false}"

// Sends a request that must be refused with 400 and must leave the Tea timer as it was.
static void rejected(const char *uri, const char *body, const char *message)
{
    post("/capsule", TEA);
    post(uri, body);
    check_count++;
    char wanted[200];
    snprintf(wanted, sizeof(wanted), "{\"error\":\"%s\"}", message);
    if (s_last.status != 400 || strcmp(s_last.req.response, wanted) != 0 || s_last.result != ESP_OK) {
        check_failures++;
        printf("  FAIL  POST %s %s\n        gave %d %s, wanted 400 %s\n", uri, body, s_last.status,
               s_last.req.response, wanted);
    }
    CHECK_STR(get_state(), TEA_STATE);
}

#define BAD_JSON "body must be a JSON object"
#define BAD_TYPE "type must be \\\"timer\\\" or \\\"counter\\\""
#define BAD_LABEL "label must be a UTF-8 string"
#define BAD_SECONDS "seconds must be a number from 1 to 359999"
#define BAD_COUNT "count must be a number from 0 to 999999"
#define BAD_RUNNING "running must be true or false"
#define BAD_MOTION "motion must be true or false"
#define BAD_ACTION "action must be one of start, pause, toggle, reset, increment, motion_on, motion_off"
#define TOO_DEEP "JSON nested too deeply"
#define HAS_NUL "body must not contain a NUL character"
#define WRONG_CAPSULE "action does not apply to the current capsule"

// ---- tests ----

static void test_server_settings(void)
{
    CHECK_INT(fake_httpd_config.server_port, 80);
    CHECK_INT(fake_httpd_config.recv_wait_timeout, 2);
    CHECK(fake_httpd_config.lru_purge_enable);
}

static void test_state_while_idle(void)
{
    CHECK_STR(get_state(), "{\"type\":\"idle\",\"label\":\"\",\"count\":0,\"seconds\":0,\"remaining_seconds\":0,"
                           "\"running\":false,\"done\":false,\"motion\":false}");
    CHECK_STATUS(200);
    CHECK_STR(s_last.req.type, "application/json");
    post("/action", "{\"action\":\"reset\"}");
    CHECK_ERROR(409, WRONG_CAPSULE);
}

static void test_routing(void)
{
    s_last = fake_request(HTTP_GET, "/nope", "", 0, 0);
    CHECK_ERROR(404, "not found");
    s_last = fake_request(HTTP_GET, "/capsule", "", 0, 0);
    CHECK_ERROR(405, "method not allowed");
    s_last = fake_request(HTTP_POST, "/state", "{}", 2, 2);
    CHECK_ERROR(405, "method not allowed");
    s_last = fake_request(HTTP_OPTIONS, "/state", "", 0, 0);
    CHECK_ERROR(405, "method not allowed");
    s_last = fake_request(HTTP_HEAD, "/state", "", 0, 0);
    CHECK_ERROR(405, "method not allowed");
    s_last = fake_request(HTTP_OPTIONS, "/nope", "", 0, 0);
    CHECK_ERROR(404, "not found");
}

static void test_capsules(void)
{
    stub_set_ms(1000);
    CHECK_STR(post("/capsule", "{\"type\":\"timer\",\"label\":\"Pasta\",\"seconds\":540}"),
              "{\"type\":\"timer\",\"label\":\"Pasta\",\"count\":0,\"seconds\":540,\"remaining_seconds\":540,"
              "\"running\":true,\"done\":false,\"motion\":false}");
    CHECK_STATUS(200);
    CHECK_STR(post("/capsule", TEA), TEA_STATE);
    CHECK_STR(post("/capsule", "{\"type\":\"counter\",\"label\":\"Squats\",\"count\":7}"),
              "{\"type\":\"counter\",\"label\":\"Squats\",\"count\":7,\"seconds\":0,\"remaining_seconds\":0,"
              "\"running\":false,\"done\":false,\"motion\":false}");

    // Defaults, limits, unknown fields, surrounding whitespace.
    post("/capsule", "{\"type\":\"counter\"}");
    CHECK_STATUS(200);
    CHECK_HAS("\"label\":\"\",\"count\":0,");
    post("/capsule", " \r\n{\"type\":\"counter\",\"count\":999999,\"colour\":\"red\",\"seconds\":\"x\"}\n ");
    CHECK_STATUS(200);
    CHECK_HAS("\"count\":999999,");
    post("/capsule", "{\"type\":\"timer\",\"seconds\":1,\"count\":-5,\"motion\":3}");
    CHECK_STATUS(200);
    CHECK_HAS("\"seconds\":1,");
    post("/capsule", "{\"type\":\"timer\",\"seconds\":359999}");
    CHECK_STATUS(200);
    CHECK_HAS("\"remaining_seconds\":359999,");
    post("/capsule", "{\"type\":\"timer\",\"seconds\":90.9}");
    CHECK_STATUS(200);
    CHECK_HAS("\"seconds\":90,");  // fractions are cut off

    // Labels: accents and emoji pass, long ones are cut on a character boundary.
    post("/capsule", "{\"type\":\"counter\",\"label\":\"Pr\xC3\xB3" "ba \\u00e9 \\ud83d\\ude00\"}");
    CHECK_STATUS(200);
    CHECK_HAS("\"label\":\"Pr\xC3\xB3" "ba \xC3\xA9 \xF0\x9F\x98\x80\"");
    post("/capsule", "{\"type\":\"counter\",\"label\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\xC3\xA9\"}");
    CHECK_HAS("\"label\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",");  // 46 a: the 2-byte char would straddle
    post("/capsule", "{\"type\":\"counter\",\"label\":\"tab\there, [brackets] {too}\"}");
    CHECK_STATUS(200);
}

static void test_rejected_capsules(void)
{
    rejected("/capsule", "", BAD_JSON);
    rejected("/capsule", "   ", BAD_JSON);
    rejected("/capsule", "{\"type\":\"timer\",\"label\":", BAD_JSON);
    rejected("/capsule", "[1,2,3]", BAD_JSON);
    rejected("/capsule", "\"timer\"", BAD_JSON);
    rejected("/capsule", "null", BAD_JSON);
    rejected("/capsule", "{\"type\":\"counter\"} x", BAD_JSON);
    rejected("/capsule", "{\"type\":\"counter\"}{}", BAD_JSON);
    rejected("/capsule", "{\"type\":\"counter\",\"x\":NaN}", BAD_JSON);

    rejected("/capsule", "{}", BAD_TYPE);
    rejected("/capsule", "{\"label\":\"x\"}", BAD_TYPE);
    rejected("/capsule", "{\"type\":\"stopwatch\"}", BAD_TYPE);
    rejected("/capsule", "{\"type\":\"Timer\",\"seconds\":5}", BAD_TYPE);
    rejected("/capsule", "{\"type\":5}", BAD_TYPE);
    rejected("/capsule", "{\"type\":null}", BAD_TYPE);
    rejected("/capsule", "{\"TYPE\":\"counter\"}", BAD_TYPE);

    rejected("/capsule", "{\"type\":\"counter\",\"label\":5}", BAD_LABEL);
    rejected("/capsule", "{\"type\":\"counter\",\"label\":null}", BAD_LABEL);
    rejected("/capsule", "{\"type\":\"timer\",\"seconds\":5,\"label\":[\"x\"]}", BAD_LABEL);

    rejected("/capsule", "{\"type\":\"timer\"}", BAD_SECONDS);
    rejected("/capsule", "{\"type\":\"timer\",\"seconds\":0}", BAD_SECONDS);
    rejected("/capsule", "{\"type\":\"timer\",\"seconds\":0.5}", BAD_SECONDS);
    rejected("/capsule", "{\"type\":\"timer\",\"seconds\":-1}", BAD_SECONDS);
    rejected("/capsule", "{\"type\":\"timer\",\"seconds\":360000}", BAD_SECONDS);
    rejected("/capsule", "{\"type\":\"timer\",\"seconds\":1e300}", BAD_SECONDS);
    rejected("/capsule", "{\"type\":\"timer\",\"seconds\":\"540\"}", BAD_SECONDS);
    rejected("/capsule", "{\"type\":\"timer\",\"seconds\":true}", BAD_SECONDS);
    rejected("/capsule", "{\"type\":\"timer\",\"seconds\":null}", BAD_SECONDS);
    rejected("/capsule", "{\"type\":\"timer\",\"seconds\":5,\"running\":1}", BAD_RUNNING);
    rejected("/capsule", "{\"type\":\"timer\",\"seconds\":5,\"running\":\"false\"}", BAD_RUNNING);

    rejected("/capsule", "{\"type\":\"counter\",\"count\":-1}", BAD_COUNT);
    rejected("/capsule", "{\"type\":\"counter\",\"count\":1000000}", BAD_COUNT);
    rejected("/capsule", "{\"type\":\"counter\",\"count\":\"3\"}", BAD_COUNT);
    rejected("/capsule", "{\"type\":\"counter\",\"motion\":\"yes\"}", BAD_MOTION);
    rejected("/capsule", "{\"type\":\"counter\",\"motion\":0}", BAD_MOTION);
}

// Labels that are not text. The mock used to die on the first one after it had already
// switched the capsule type; the board stored the raw bytes.
static void test_rejected_labels(void)
{
    // A lone surrogate escape is not a character: cJSON refuses the whole body.
    rejected("/capsule", "{\"type\":\"counter\",\"label\":\"\\ud83d\"}", BAD_JSON);
    rejected("/capsule", "{\"type\":\"counter\",\"label\":\"\\ude00\"}", BAD_JSON);
    rejected("/capsule", "{\"type\":\"counter\",\"label\":\"\\ud83dx\"}", BAD_JSON);
    // Raw bytes that are not UTF-8 get through cJSON and are stopped by apply_capsule().
    rejected("/capsule", "{\"type\":\"counter\",\"label\":\"a\xFF" "b\"}", BAD_LABEL);
    rejected("/capsule", "{\"type\":\"counter\",\"label\":\"\x80\"}", BAD_LABEL);
    rejected("/capsule", "{\"type\":\"counter\",\"label\":\"caf\xC3\"}", BAD_LABEL);
    rejected("/capsule", "{\"type\":\"counter\",\"label\":\"\xC0\x80\"}", BAD_LABEL);
    rejected("/capsule", "{\"type\":\"counter\",\"label\":\"\xED\xA0\xBD\"}", BAD_LABEL);
    rejected("/capsule", "{\"type\":\"timer\",\"seconds\":5,\"label\":\"\xF5\x80\x80\x80\"}", BAD_LABEL);
    // NUL would silently end the label.
    rejected("/capsule", "{\"type\":\"counter\",\"label\":\"a\\u0000b\"}", HAS_NUL);
    rejected("/action", "{\"action\":\"reset\\u0000\"}", HAS_NUL);
    post("/capsule", TEA);
    s_last = fake_request(HTTP_POST, "/capsule", "{\"type\":\"counter\",\"label\":\"a\0b\"}", 33, 33);
    CHECK_ERROR(400, HAS_NUL);
    CHECK_STR(get_state(), TEA_STATE);
    // Bytes that are not UTF-8 outside the label are not looked at.
    post("/capsule", "{\"type\":\"counter\",\"label\":\"ok\",\"note\":\"\xFF\"}");
    CHECK_STATUS(200);
}

// Finding 1: cJSON recurses once per level; 300 levels overflowed the HTTP task's stack.
static void test_nesting_limit(void)
{
    char deep[1025];
    memset(deep, '[', 300);
    deep[300] = '\0';
    rejected("/capsule", deep, TOO_DEEP);
    rejected("/action", deep, TOO_DEEP);
    memset(deep, '{', 1024);
    deep[1024] = '\0';
    rejected("/capsule", deep, TOO_DEEP);
    rejected("/action", deep, TOO_DEEP);
    for (int i = 0; i < 340; i++) {
        memcpy(deep + 3 * i, "[{\"", 3);  // [{"[{"[{"... : every other bracket is inside a string
    }
    deep[1020] = '\0';
    rejected("/capsule", deep, TOO_DEEP);

    // Well-formed and only one level too deep: still refused, as documented.
    rejected("/capsule", "{\"type\":\"counter\",\"x\":[[[[[[[[1]]]]]]]]}", TOO_DEEP);
    rejected("/action", "{\"action\":\"reset\",\"x\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{}}}}}}}}}", TOO_DEEP);
    // Eight levels are fine, and so are brackets that are only text.
    post("/capsule", "{\"type\":\"counter\",\"x\":[[[[[[[1]]]]]]]}");
    CHECK_STATUS(200);
    post("/capsule", "{\"type\":\"counter\",\"label\":\"[[[[[[[[[[{{{{{{{{{{\"}");
    CHECK_STATUS(200);
    CHECK_HAS("\"label\":\"[[[[[[[[[[{{{{{{{{{{\"");
    post("/capsule", "{\"type\":\"counter\",\"label\":\"a\\\"[[[[[[[[[[\"}");
    CHECK_STATUS(200);
    CHECK_HAS("\"label\":\"a\\\"[[[[[[[[[[\"");
    post("/action", "{\"action\":\"increment\",\"why\":\"[[[[[[[[[[[[[[[[\"}");
    CHECK_STATUS(200);
}

// Finding 4: where the body was not read to its end, the handler must return ESP_FAIL so
// that the server closes the socket instead of draining it. A body that is a little too
// large is read and thrown away (at most 8192 bytes of it): on the board, closing with
// unread data reset the connection and the client lost the 413.
static void test_body_limits(void)
{
    static char body[20000];
    memset(body, ' ', sizeof(body));
    memcpy(body, TEA, strlen(TEA));

    // Exactly 1024 bytes is accepted (and arrives in several pieces).
    s_last = fake_request(HTTP_POST, "/capsule", body, 1024, 1024);
    CHECK_STATUS(200);
    CHECK_INT(s_last.result, ESP_OK);
    CHECK_INT(s_last.req.body_read, 1024);

    // One more is refused. The body is read and dropped, and the connection can stay.
    post("/capsule", "{\"type\":\"counter\",\"label\":\"before\"}");
    s_last = fake_request(HTTP_POST, "/capsule", body, 1025, 1025);
    CHECK_ERROR(413, "body too large");
    CHECK_INT(s_last.result, ESP_OK);
    CHECK_INT(s_last.req.body_read, 1025);
    s_last = fake_request(HTTP_POST, "/action", body, 8192, 8192);
    CHECK_ERROR(413, "body too large");
    CHECK_INT(s_last.result, ESP_OK);
    CHECK_INT(s_last.req.body_read, 8192);
    // Larger than that: answered, 8192 bytes dropped, then the socket is closed.
    s_last = fake_request(HTTP_POST, "/capsule", body, 20000, 20000);
    CHECK_ERROR(413, "body too large");
    CHECK_INT(s_last.result, ESP_FAIL);
    CHECK_INT(s_last.req.body_read, 8192);
    s_last = fake_request(HTTP_POST, "/action", body, 8193, 8193);
    CHECK_INT(s_last.result, ESP_FAIL);
    // An absurd Content-Length with little behind it, or nothing: closed as soon as it stalls.
    s_last = fake_request(HTTP_POST, "/action", body, 2000, (size_t)-1);
    CHECK_ERROR(413, "body too large");
    CHECK_INT(s_last.result, ESP_FAIL);
    CHECK_INT(s_last.req.body_read, 2000);
    s_last = fake_request(HTTP_POST, "/capsule", body, 0, 5000);
    CHECK_ERROR(413, "body too large");
    CHECK_INT(s_last.result, ESP_FAIL);

    // The client announces 500 bytes and sends 100, or none.
    s_last = fake_request(HTTP_POST, "/capsule", body, 100, 500);
    CHECK_ERROR(408, "body not received");
    CHECK_INT(s_last.result, ESP_FAIL);
    s_last = fake_request(HTTP_POST, "/action", body, 0, 20);
    CHECK_ERROR(408, "body not received");
    CHECK_INT(s_last.result, ESP_FAIL);
    get_state();
    CHECK_HAS("\"label\":\"before\"");

    // An ordinary 400 has read the whole body: the connection can stay open.
    post("/capsule", "[]");
    CHECK_STATUS(400);
    CHECK_INT(s_last.result, ESP_OK);
}

static void test_actions(void)
{
    post("/capsule", "{\"type\":\"counter\",\"label\":\"Reps\",\"count\":1}");
    post("/action", "{\"action\":\"increment\"}");
    CHECK_STATUS(200);
    CHECK_HAS("\"count\":2,");
    post("/action", "{\"action\":\"reset\"}");
    CHECK_HAS("\"count\":0,");
    post("/action", "{\"action\":\"start\"}");
    CHECK_ERROR(409, WRONG_CAPSULE);
    post("/action", "{\"action\":\"pause\"}");
    CHECK_ERROR(409, WRONG_CAPSULE);
    post("/action", "{\"action\":\"toggle\"}");
    CHECK_ERROR(409, WRONG_CAPSULE);

    stub_set_ms(1000);
    post("/capsule", "{\"type\":\"timer\",\"label\":\"Pasta\",\"seconds\":540}");
    stub_set_ms(3500);
    post("/action", "{\"action\":\"pause\"}");
    CHECK_HAS("\"remaining_seconds\":538,\"running\":false,");
    post("/action", "{\"action\":\"toggle\"}");
    CHECK_HAS("\"running\":true,");
    post("/action", "{\"action\":\"reset\"}");
    CHECK_HAS("\"remaining_seconds\":540,\"running\":false,");
    post("/action", "{\"action\":\"start\"}");
    CHECK_HAS("\"running\":true,");
    post("/action", "{\"action\":\"increment\"}");
    CHECK_ERROR(409, WRONG_CAPSULE);
    post("/action", "{\"action\":\"motion_off\"}");
    CHECK_ERROR(409, WRONG_CAPSULE);

    rejected("/action", "{\"action\":\"explode\"}", BAD_ACTION);
    rejected("/action", "{\"action\":\"Start\"}", BAD_ACTION);
    rejected("/action", "{\"action\":5}", BAD_ACTION);
    rejected("/action", "{}", BAD_ACTION);
    rejected("/action", "{\"type\":\"counter\"}", BAD_ACTION);
    rejected("/action", "\"start\"", BAD_JSON);
    rejected("/action", "", BAD_JSON);
}

// Finding 3: motion_on answers 409 wherever it does not apply, sensor or no sensor;
// 503 is only for a counter on a board whose sensor did not start.
static void test_motion(void)
{
    s_motion_sensor = true;
    post("/capsule", "{\"type\":\"counter\",\"motion\":true}");
    CHECK_HAS("\"motion\":true}");
    post("/action", "{\"action\":\"motion_off\"}");
    CHECK_HAS("\"motion\":false}");
    post("/action", "{\"action\":\"motion_on\"}");
    CHECK_STATUS(200);
    CHECK_HAS("\"motion\":true}");
    post("/capsule", TEA);
    post("/action", "{\"action\":\"motion_on\"}");
    CHECK_ERROR(409, WRONG_CAPSULE);

    s_motion_sensor = false;
    post("/action", "{\"action\":\"motion_on\"}");  // still the Tea timer
    CHECK_ERROR(409, WRONG_CAPSULE);
    CHECK_STR(get_state(), TEA_STATE);
    post("/capsule", "{\"type\":\"counter\",\"motion\":true}");
    CHECK_STATUS(200);
    CHECK_HAS("\"motion\":false}");  // the counter still works by hand
    post("/action", "{\"action\":\"motion_on\"}");
    CHECK_ERROR(503, "motion sensor not available");
    get_state();
    CHECK_HAS("\"motion\":false}");
    post("/action", "{\"action\":\"motion_off\"}");
    CHECK_STATUS(200);
    s_motion_sensor = true;
}

static void test_screenshot(void)
{
    s_screen_width = 0;
    s_last = fake_request(HTTP_GET, "/screenshot", "", 0, 0);
    CHECK_ERROR(503, "display not available");

    s_screen_width = 4;
    s_screen_height = 2;
    s_last = fake_request(HTTP_GET, "/screenshot", "", 0, 0);
    CHECK_STATUS(200);
    CHECK_INT(s_last.result, ESP_OK);
    CHECK_STR(s_last.req.type, "image/bmp");
    const unsigned char *bmp = (const unsigned char *)s_last.req.response;
    CHECK_INT(s_last.req.response_len, 54 + 4 * 2 * 3);
    CHECK(bmp[0] == 'B' && bmp[1] == 'M');
    CHECK_INT(bmp[2], 54 + 24);  // file size
    CHECK_INT(bmp[18], 4);
    CHECK_INT(bmp[22], 2);
    // Rows are stored bottom-up as B, G, R: the red top-left pixel starts the second row.
    CHECK(bmp[54] == 0 && bmp[55] == 255 && bmp[56] == 0);
    CHECK(bmp[54 + 12] == 0 && bmp[54 + 13] == 0 && bmp[54 + 14] == 255);
    s_screen_width = 0;
}

int main(void)
{
    capsule_init();
    http_api_start();
    test_server_settings();
    test_state_while_idle();
    test_routing();
    test_capsules();
    test_rejected_capsules();
    test_rejected_labels();
    test_nesting_limit();
    test_body_limits();
    test_actions();
    test_motion();
    test_screenshot();
    return check_report("test_http_api");
}

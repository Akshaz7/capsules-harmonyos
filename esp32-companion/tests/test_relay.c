// Host tests for main/relay_sync.c: reading the relay's answers, when a capsule or an action
// from the relay is applied, when state is reported, and the backoff schedule.
// relay_sync.c, capsule_json.c and capsule.c are the firmware's own files.
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#include "capsule.h"
#include "capsule_json.h"
#include "check.h"
#include "motion.h"
#include "relay_sync.h"
#include "stubs.h"

static bool s_motion_sensor = true;

bool motion_available(void)
{
    return s_motion_sensor;
}

// ---- helpers ----

static relay_sync_t s_sync;

static relay_poll_t poll(const char *body)
{
    relay_poll_t result = relay_handle_poll(&s_sync, body, strlen(body));
    CHECK_INT(stub_lock_depth, 0);
    return result;
}

static capsule_state_t state(void)
{
    capsule_state_t now;
    capsule_get(&now);
    return now;
}

static void fresh(void)  // as after a registration, with a known capsule on screen
{
    relay_sync_reset(&s_sync);
    capsule_set_timer("Tea", 180, false);
}

#define EMPTY "{\"claimed\":false,\"version\":0,\"capsule\":null,\"action_seq\":0,\"action\":null}"
#define SQUATS(version, seq, action)                                                                \
    "{\"claimed\":true,\"version\":" #version ",\"capsule\":{\"type\":\"counter\",\"label\":\"Squats\"," \
    "\"count\":3},\"action_seq\":" #seq ",\"action\":" action "}"

// ---- registration ----

static void test_register_body(void)
{
    char *body = relay_register_body("0123456789abcdef", "1.2.3");
    CHECK_STR(body, "{\"hw\":\"0123456789abcdef\",\"kind\":\"wrist\",\"fw\":\"1.2.3\"}");
    cJSON_free(body);
}

static bool parse_register(const char *body, relay_credentials_t *out)
{
    return relay_parse_register(body, strlen(body), out);
}

static void test_parse_register(void)
{
    relay_credentials_t got;
    CHECK(parse_register("{\"id\":\"dev_1a\",\"token\":\"abc.DEF-123_~+/=\",\"code\":\"brave-otter-lamp\"}", &got));
    CHECK_STR(got.id, "dev_1a");
    CHECK_STR(got.token, "abc.DEF-123_~+/=");
    CHECK_STR(got.code, "brave-otter-lamp");
    // Unknown fields are ignored.
    CHECK(parse_register("{\"id\":\"a\",\"token\":\"b\",\"code\":\"tiny-fox-drum\",\"extra\":[1,2]}", &got));
    CHECK_STR(got.id, "a");

    relay_credentials_t kept = got;
    static const char *const refused[] = {
        "",
        "null",
        "[]",
        "{}",
        "{\"id\":\"a\",\"token\":\"b\"}",
        "{\"id\":\"a\",\"code\":\"brave-otter-lamp\"}",
        "{\"token\":\"b\",\"code\":\"brave-otter-lamp\"}",
        "{\"id\":1,\"token\":\"b\",\"code\":\"brave-otter-lamp\"}",
        "{\"id\":\"a\",\"token\":\"b\",\"code\":123456}",
        "{\"id\":\"\",\"token\":\"b\",\"code\":\"brave-otter-lamp\"}",
        "{\"id\":\"a\",\"token\":\"\",\"code\":\"brave-otter-lamp\"}",
        "{\"id\":\"a\",\"token\":\"b\",\"code\":\"\"}",
        "{\"id\":\"a\",\"token\":\"b\",\"code\":\"abcdefghij-abcdefghij-abcdefghijk\"}",  // 33 bytes
        "{\"id\":\"a\",\"token\":\"b\",\"code\":\"brave\\notter\"}",   // a control character
        "{\"id\":\"a\",\"token\":\"b\",\"code\":\"caf\xc3\xa9-otter-lamp\"}",  // not ASCII: the small font has no glyph
        "{\"id\":\"a/b\",\"token\":\"b\",\"code\":\"brave-otter-lamp\"}",         // would change the URL path
        "{\"id\":\"../x\",\"token\":\"b\",\"code\":\"brave-otter-lamp\"}",
        "{\"id\":\"a?b\",\"token\":\"b\",\"code\":\"brave-otter-lamp\"}",
        "{\"id\":\"a\",\"token\":\"b c\",\"code\":\"brave-otter-lamp\"}",
        "{\"id\":\"a\",\"token\":\"b\\r\\nX: y\",\"code\":\"brave-otter-lamp\"}",  // would add a header
        "{\"id\":\"a\",\"token\":\"b\",\"code\":\"brave-otter-lamp\"} x",
        "{\"id\":\"a\",\"token\":\"b\",\"code\":\"brave-otter-lamp\",\"x\":[[[[[[[[1]]]]]]]]}",  // nested 9 deep
    };
    for (size_t i = 0; i < sizeof(refused) / sizeof(refused[0]); i++) {
        check_count++;
        if (parse_register(refused[i], &got)) {
            check_failures++;
            printf("  FAIL  register answer accepted: %s\n", refused[i]);
        }
    }
    CHECK(memcmp(&got, &kept, sizeof(got)) == 0);  // a refused answer leaves *out alone
}

static void test_register_lengths(void)
{
    char body[512];
    char id[RELAY_ID_MAX + 2], token[RELAY_TOKEN_MAX + 2];
    relay_credentials_t got;
    for (int over = 0; over <= 1; over++) {
        memset(id, 'i', RELAY_ID_MAX + over);
        id[RELAY_ID_MAX + over] = '\0';
        snprintf(body, sizeof(body), "{\"id\":\"%s\",\"token\":\"t\",\"code\":\"brave-otter-lamp\"}", id);
        CHECK_INT(parse_register(body, &got), !over);
        memset(token, 't', RELAY_TOKEN_MAX + over);
        token[RELAY_TOKEN_MAX + over] = '\0';
        snprintf(body, sizeof(body), "{\"id\":\"i\",\"token\":\"%s\",\"code\":\"brave-otter-lamp\"}", token);
        CHECK_INT(parse_register(body, &got), !over);
    }
    CHECK_INT(strlen(got.token), RELAY_TOKEN_MAX);
}

static void test_code_ok(void)
{
    // The board does not interpret the code, it only has to be able to show it.
    CHECK(relay_printable("brave-otter-lamp", RELAY_CODE_MAX));
    CHECK(relay_printable("Brave Otter Lamp", RELAY_CODE_MAX));
    CHECK(relay_printable("123456", RELAY_CODE_MAX));
    CHECK(relay_printable("abcdefghij-abcdefghij-abcdefghij", RELAY_CODE_MAX));  // 32 bytes
    CHECK(!relay_printable("abcdefghij-abcdefghij-abcdefghijk", RELAY_CODE_MAX));
    CHECK(!relay_printable("", RELAY_CODE_MAX));
    CHECK(!relay_printable("a\tb", RELAY_CODE_MAX));
    CHECK(!relay_printable("a\x7f", RELAY_CODE_MAX));
    CHECK(!relay_printable("\xff", RELAY_CODE_MAX));
}

static void test_poll_code(void)
{
    fresh();
    CHECK_STR(poll(EMPTY).code, "");  // none given
    CHECK_STR(poll("{\"claimed\":false,\"version\":0,\"capsule\":null,\"action_seq\":0,\"action\":null,"
                   "\"code\":\"quiet-maple-drum\"}").code, "quiet-maple-drum");
    CHECK_STR(poll("{\"claimed\":true,\"version\":0,\"capsule\":null,\"action_seq\":0,\"code\":null}").code, "");
    // One that cannot be shown is left out; the answer is still good.
    relay_poll_t result = poll("{\"claimed\":false,\"version\":0,\"capsule\":null,\"action_seq\":0,\"code\":7}");
    CHECK(result.ok);
    CHECK_STR(result.code, "");
    result = poll("{\"claimed\":false,\"version\":0,\"capsule\":null,\"action_seq\":0,"
                  "\"code\":\"abcdefghij-abcdefghij-abcdefghijk\"}");
    CHECK(result.ok);
    CHECK_STR(result.code, "");
}

static void test_pair_url(void)
{
    relay_credentials_t got;
    CHECK(parse_register("{\"id\":\"a\",\"token\":\"b\",\"code\":\"brave-otter-lamp\","
                         "\"pair_url\":\"https://example.com/pair?code=brave-otter-lamp\"}", &got));
    CHECK_STR(got.pair_url, "https://example.com/pair?code=brave-otter-lamp");
    // Optional: without it, or with one that cannot be drawn, the phrase alone is shown.
    CHECK(parse_register("{\"id\":\"a\",\"token\":\"b\",\"code\":\"brave-otter-lamp\"}", &got));
    CHECK_STR(got.pair_url, "");
    CHECK(parse_register("{\"id\":\"a\",\"token\":\"b\",\"code\":\"brave-otter-lamp\",\"pair_url\":null}", &got));
    CHECK_STR(got.pair_url, "");
    CHECK(parse_register("{\"id\":\"a\",\"token\":\"b\",\"code\":\"brave-otter-lamp\",\"pair_url\":\"\"}", &got));
    CHECK_STR(got.pair_url, "");
    CHECK(parse_register("{\"id\":\"a\",\"token\":\"b\",\"code\":\"brave-otter-lamp\",\"pair_url\":\"a\\nb\"}", &got));
    CHECK_STR(got.pair_url, "");

    char body[512], url[RELAY_PAIR_URL_MAX + 2];
    for (int over = 0; over <= 1; over++) {
        memset(url, 'u', RELAY_PAIR_URL_MAX + over);
        url[RELAY_PAIR_URL_MAX + over] = '\0';
        snprintf(body, sizeof(body), "{\"id\":\"a\",\"token\":\"b\",\"code\":\"c\",\"pair_url\":\"%s\"}", url);
        CHECK(parse_register(body, &got));
        CHECK_INT(strlen(got.pair_url), over ? 0 : RELAY_PAIR_URL_MAX);
    }

    fresh();
    relay_poll_t result = poll("{\"claimed\":false,\"version\":0,\"capsule\":null,\"action_seq\":0,"
                               "\"code\":\"quiet-maple-drum\",\"pair_url\":\"http://10.0.0.1:8090/pair?code=quiet-maple-drum\"}");
    CHECK_STR(result.code, "quiet-maple-drum");
    CHECK_STR(result.pair_url, "http://10.0.0.1:8090/pair?code=quiet-maple-drum");
    // A URL without a code belongs to nothing.
    result = poll("{\"claimed\":false,\"version\":0,\"capsule\":null,\"action_seq\":0,\"pair_url\":\"http://x/pair\"}");
    CHECK(result.ok);
    CHECK_STR(result.pair_url, "");
}

static void test_take_pairing(void)
{
    relay_credentials_t held = { .id = "a", .token = "b", .code = "brave-otter-lamp", .pair_url = "http://x/pair?code=1" };
    relay_credentials_t before = held;
    relay_poll_t answer = { .ok = true };

    CHECK(!relay_take_pairing(&held, &answer));  // a relay that says nothing about codes in a poll
    strcpy(answer.code, "brave-otter-lamp");
    CHECK(!relay_take_pairing(&held, &answer));  // same code, no URL: the one from the registration stays
    strcpy(answer.pair_url, "http://x/pair?code=1");
    CHECK(!relay_take_pairing(&held, &answer));
    CHECK(memcmp(&held, &before, sizeof(held)) == 0);

    strcpy(answer.code, "quiet-maple-drum");
    strcpy(answer.pair_url, "http://x/pair?code=2");
    CHECK(relay_take_pairing(&held, &answer));
    CHECK_STR(held.code, "quiet-maple-drum");
    CHECK_STR(held.pair_url, "http://x/pair?code=2");
    CHECK_STR(held.token, "b");

    strcpy(answer.code, "tiny-fox-drum");  // a new code without a URL: the old QR code must go
    answer.pair_url[0] = '\0';
    CHECK(relay_take_pairing(&held, &answer));
    CHECK_STR(held.code, "tiny-fox-drum");
    CHECK_STR(held.pair_url, "");

    strcpy(answer.pair_url, "http://x/pair?code=3");  // same code, the URL arrives later
    CHECK(relay_take_pairing(&held, &answer));
    CHECK_STR(held.pair_url, "http://x/pair?code=3");

    before = held;
    strcpy(answer.code, "calm-owl-jar");
    answer.claimed = true;  // claimed: nothing to pair any more
    CHECK(!relay_take_pairing(&held, &answer));
    CHECK(memcmp(&held, &before, sizeof(held)) == 0);
}

static void test_text_ok(void)
{
    CHECK(relay_text_ok("abcXYZ019", 9, ""));
    CHECK(!relay_text_ok("abcXYZ019", 8, ""));
    CHECK(!relay_text_ok("", 8, ""));
    CHECK(relay_text_ok("a-b", 8, "-"));
    CHECK(!relay_text_ok("a-b", 8, ""));
    CHECK(!relay_text_ok("a\xc3\xa9", 8, "-"));
}

// ---- polling ----

static void test_poll_nothing_to_do(void)
{
    fresh();
    relay_poll_t result = poll(EMPTY);
    CHECK(result.ok);
    CHECK(!result.claimed);
    CHECK(!result.capsule_applied && !result.capsule_error && !result.action_applied && !result.action_skipped);
    CHECK_STR(state().label, "Tea");
    CHECK_INT(relay_shown_version(&s_sync), 0);
    CHECK_INT(s_sync.version, 0);
}

static void test_poll_applies_a_new_version_once(void)
{
    fresh();
    relay_poll_t result = poll(SQUATS(1, 0, "null"));
    CHECK(result.ok && result.claimed && result.capsule_applied);
    CHECK_INT(state().type, CAPSULE_COUNTER);
    CHECK_STR(state().label, "Squats");
    CHECK_INT(state().count, 3);
    CHECK_INT(relay_shown_version(&s_sync), 1);

    // The same version again: the count made on the wrist must survive.
    capsule_apply(CAPSULE_ACT_INCREMENT);
    result = poll(SQUATS(1, 0, "null"));
    CHECK(result.ok && !result.capsule_applied);
    CHECK_INT(state().count, 4);
    CHECK_INT(relay_shown_version(&s_sync), 1);  // an action does not make it another capsule

    // A new version replaces it, also when the number went down (only equality counts).
    result = poll(SQUATS(7, 0, "null"));
    CHECK(result.capsule_applied);
    CHECK_INT(state().count, 3);
    CHECK_INT(relay_shown_version(&s_sync), 7);
    result = poll(SQUATS(2, 0, "null"));
    CHECK(result.capsule_applied);
    CHECK_INT(relay_shown_version(&s_sync), 2);
}

static void test_poll_timer(void)
{
    fresh();
    stub_set_ms(1000);
    relay_poll_t result = poll("{\"claimed\":true,\"version\":1,\"capsule\":{\"type\":\"timer\",\"label\":\"Pasta\","
                               "\"seconds\":540},\"action_seq\":0,\"action\":null}");
    CHECK(result.capsule_applied);
    CHECK_INT(state().type, CAPSULE_TIMER);
    CHECK_INT(state().seconds, 540);
    CHECK(state().running);
    stub_advance_ms(30000);
    poll("{\"claimed\":true,\"version\":1,\"capsule\":{\"type\":\"timer\",\"label\":\"Pasta\",\"seconds\":540},"
         "\"action_seq\":0,\"action\":null}");
    CHECK_INT(state().remaining_seconds, 510);  // not restarted by the repeated answer
}

static void test_local_capsule_wins_until_the_next_version(void)
{
    fresh();
    poll(SQUATS(1, 0, "null"));
    capsule_set_counter("Local", 9, false);  // POST /capsule on the local API
    CHECK_INT(relay_shown_version(&s_sync), 0);
    relay_poll_t result = poll(SQUATS(1, 0, "null"));
    CHECK(!result.capsule_applied);
    CHECK_STR(state().label, "Local");
    CHECK_INT(relay_shown_version(&s_sync), 0);
    result = poll(SQUATS(2, 0, "null"));
    CHECK(result.capsule_applied);
    CHECK_STR(state().label, "Squats");
    CHECK_INT(relay_shown_version(&s_sync), 2);
}

static void test_poll_refused_capsule(void)
{
    fresh();
    poll(SQUATS(1, 0, "null"));
    static const char *const bad[] = {
        "{\"type\":\"timer\",\"label\":\"x\"}",
        "{\"type\":\"timer\",\"seconds\":0}",
        "{\"type\":\"timer\",\"seconds\":360000}",
        "{\"type\":\"counter\",\"count\":-1}",
        "{\"type\":\"counter\",\"label\":7}",
        "{\"type\":\"counter\",\"label\":\"a\xff\"}",
        "{\"type\":\"stopwatch\"}",
        "{}",
    };
    for (size_t i = 0; i < sizeof(bad) / sizeof(bad[0]); i++) {
        char body[256];
        snprintf(body, sizeof(body), "{\"claimed\":true,\"version\":%d,\"capsule\":%s,\"action_seq\":0,\"action\":null}",
                 (int)i + 2, bad[i]);
        relay_poll_t result = poll(body);
        CHECK(result.ok);  // the relay answered; it is the capsule that is wrong
        CHECK(result.capsule_error != NULL);
        CHECK(!result.capsule_applied);
        CHECK_STR(state().label, "Squats");
        CHECK_INT(relay_shown_version(&s_sync), 1);  // still showing version 1
        CHECK_INT(s_sync.version, (int)i + 2);       // and not tried again every 2 seconds
        result = poll(body);
        CHECK(result.capsule_error == NULL);
    }
    CHECK_STR(poll("{\"claimed\":true,\"version\":50,\"capsule\":{\"type\":\"timer\"},\"action_seq\":0}").capsule_error,
              ERR_BAD_SECONDS);
}

static void test_poll_capsule_null_keeps_the_screen(void)
{
    fresh();
    poll(SQUATS(1, 0, "null"));
    relay_poll_t result = poll("{\"claimed\":true,\"version\":2,\"capsule\":null,\"action_seq\":0,\"action\":null}");
    CHECK(result.ok && !result.capsule_applied && !result.capsule_error);
    CHECK_STR(state().label, "Squats");
    CHECK_INT(s_sync.version, 2);
    CHECK_INT(relay_shown_version(&s_sync), 1);
}

static void test_poll_actions(void)
{
    fresh();
    poll(SQUATS(1, 0, "null"));
    relay_poll_t result = poll(SQUATS(1, 1, "\"increment\""));
    CHECK(result.action_applied);
    CHECK_INT(state().count, 4);
    result = poll(SQUATS(1, 1, "\"increment\""));  // same action_seq: once only
    CHECK(!result.action_applied && !result.action_skipped);
    CHECK_INT(state().count, 4);
    poll(SQUATS(1, 2, "\"increment\""));
    CHECK_INT(state().count, 5);
    result = poll(SQUATS(1, 3, "\"reset\""));
    CHECK(result.action_applied);
    CHECK_INT(state().count, 0);

    // Does not fit a counter, or is no action at all: skipped, and not tried again.
    result = poll(SQUATS(1, 4, "\"pause\""));
    CHECK(result.ok && result.action_skipped && !result.action_applied);
    result = poll(SQUATS(1, 4, "\"pause\""));
    CHECK(!result.action_skipped);
    result = poll(SQUATS(1, 5, "\"explode\""));
    CHECK(result.action_skipped);
    result = poll(SQUATS(1, 6, "null"));
    CHECK(!result.action_skipped && !result.action_applied);
    CHECK_INT(s_sync.action_seq, 6);

    // A new capsule and a new action in one answer: the capsule first.
    result = poll(SQUATS(2, 7, "\"increment\""));
    CHECK(result.capsule_applied && result.action_applied);
    CHECK_INT(state().count, 4);
}

static void test_poll_motion_without_a_sensor(void)
{
    fresh();
    poll(SQUATS(1, 0, "null"));
    s_motion_sensor = false;
    relay_poll_t result = poll(SQUATS(1, 1, "\"motion_on\""));
    CHECK(result.action_skipped);
    CHECK(!state().motion);
    s_motion_sensor = true;
    result = poll(SQUATS(1, 2, "\"motion_on\""));
    CHECK(result.action_applied);
    CHECK(state().motion);
}

static void test_first_poll_does_not_replay_an_old_action(void)
{
    fresh();  // the board restarted; the relay still holds action 5 from before
    relay_poll_t result = poll(SQUATS(4, 5, "\"increment\""));
    CHECK(result.capsule_applied);  // the capsule comes back ...
    CHECK(!result.action_applied && !result.action_skipped);
    CHECK_INT(state().count, 3);    // ... the old tap does not
    result = poll(SQUATS(4, 5, "\"increment\""));
    CHECK(!result.action_applied);
    result = poll(SQUATS(4, 6, "\"increment\""));
    CHECK(result.action_applied);
    CHECK_INT(state().count, 4);
}

static void test_poll_unusable_answers(void)
{
    static const char *const unusable[] = {
        "",
        "null",
        "[1]",
        "{}",
        "<html>502 Bad Gateway</html>",
        "{\"version\":1,\"capsule\":null,\"action_seq\":0}",                            // no claimed
        "{\"claimed\":1,\"version\":1,\"capsule\":null,\"action_seq\":0}",
        "{\"claimed\":true,\"capsule\":null,\"action_seq\":0}",                         // no version
        "{\"claimed\":true,\"version\":\"1\",\"capsule\":null,\"action_seq\":0}",
        "{\"claimed\":true,\"version\":-1,\"capsule\":null,\"action_seq\":0}",
        "{\"claimed\":true,\"version\":1.5,\"capsule\":null,\"action_seq\":0}",
        "{\"claimed\":true,\"version\":1e300,\"capsule\":null,\"action_seq\":0}",
        "{\"claimed\":true,\"version\":1,\"capsule\":null}",                            // no action_seq
        "{\"claimed\":true,\"version\":1,\"capsule\":null,\"action_seq\":null}",
        "{\"claimed\":true,\"version\":1,\"capsule\":[],\"action_seq\":0}",
        "{\"claimed\":true,\"version\":1,\"capsule\":\"timer\",\"action_seq\":0}",
        "{\"claimed\":true,\"version\":1,\"capsule\":null,\"action_seq\":1,\"action\":3}",
        "{\"claimed\":true,\"version\":1,\"capsule\":null,\"action_seq\":0} trailing",
        "{\"claimed\":true,\"version\":1,\"capsule\":{\"type\":\"counter\",\"x\":[[[[[[[1]]]]]]]},\"action_seq\":0}",
    };
    fresh();
    poll(SQUATS(1, 0, "null"));
    relay_sync_t before = s_sync;
    for (size_t i = 0; i < sizeof(unusable) / sizeof(unusable[0]); i++) {
        relay_poll_t result = poll(unusable[i]);
        check_count++;
        if (result.ok || result.capsule_applied || result.action_applied) {
            check_failures++;
            printf("  FAIL  poll answer accepted: %s\n", unusable[i]);
        }
    }
    CHECK(memcmp(&s_sync, &before, sizeof(s_sync)) == 0);
    CHECK_STR(state().label, "Squats");
}

static void test_poll_deep_nesting_is_refused_before_parsing(void)
{
    // What crashed the HTTP task before json_scan(): cJSON recursing once per bracket.
    enum { DEPTH = 1500 };
    char *body = malloc(DEPTH + 64);
    int head = sprintf(body, "{\"claimed\":true,\"version\":2,\"capsule\":");
    memset(body + head, '[', DEPTH);
    body[head + DEPTH] = '\0';
    fresh();
    relay_poll_t result = poll(body);
    CHECK(!result.ok);
    CHECK_INT(s_sync.version, -1);
    free(body);
}

static void test_poll_large_versions(void)
{
    fresh();
    relay_poll_t result = poll("{\"claimed\":true,\"version\":1759512345678,\"capsule\":{\"type\":\"counter\"},"
                               "\"action_seq\":9007199254740992,\"action\":null}");
    CHECK(result.ok && result.capsule_applied);
    CHECK_INT(relay_shown_version(&s_sync), 1759512345678LL);
    CHECK_INT(s_sync.action_seq, 9007199254740992LL);
}

// ---- reporting ----

static void test_report_body(void)
{
    stub_set_ms(0);
    capsule_set_timer("Tea", 180, false);
    relay_report_t report = { .state = state(), .version = 12 };
    char *body = relay_report_body(&report);
    CHECK_STR(body, "{\"type\":\"timer\",\"label\":\"Tea\",\"count\":0,\"seconds\":180,\"remaining_seconds\":180,"
                    "\"running\":false,\"done\":false,\"motion\":false,\"version\":12}");
    cJSON_free(body);
    report.version = 1759512345678LL;
    body = relay_report_body(&report);
    CHECK(strstr(body, "\"version\":1759512345678}") != NULL);
    cJSON_free(body);
}

static void test_report_due(void)
{
    relay_report_t last = { .version = 1 };
    last.state.type = CAPSULE_COUNTER;
    strcpy(last.state.label, "Squats");
    relay_report_t now = last;

    CHECK(relay_report_due(NULL, &now, 0));  // nothing delivered yet
    CHECK(!relay_report_due(&last, &now, 0));
    CHECK(!relay_report_due(&last, &now, RELAY_HEARTBEAT_MS - 1));
    CHECK(relay_report_due(&last, &now, RELAY_HEARTBEAT_MS));

    now.state.count = 1;  // a tap on +
    CHECK(relay_report_due(&last, &now, RELAY_MIN_POST_GAP_MS));
    CHECK(!relay_report_due(&last, &now, RELAY_MIN_POST_GAP_MS - 1));  // not a post per tap

    // Every field that counts as a change.
    now = last, now.version = 2;
    CHECK(relay_report_due(&last, &now, 5000));
    now = last, now.state.type = CAPSULE_TIMER;
    CHECK(relay_report_due(&last, &now, 5000));
    now = last, strcpy(now.state.label, "Lunges");
    CHECK(relay_report_due(&last, &now, 5000));
    now = last, now.state.seconds = 60;
    CHECK(relay_report_due(&last, &now, 5000));
    now = last, now.state.motion = true;
    CHECK(relay_report_due(&last, &now, 5000));
    now = last, now.state.running = true;
    CHECK(relay_report_due(&last, &now, 5000));
    now = last, now.state.done = true;
    CHECK(relay_report_due(&last, &now, 5000));
}

static void test_report_running_timer_is_not_posted_every_second(void)
{
    stub_set_ms(0);
    capsule_set_timer("Pasta", 540, true);
    relay_report_t last = { .state = state(), .version = 1 };
    stub_advance_ms(5000);
    relay_report_t now = { .state = state(), .version = 1 };
    CHECK_INT(now.state.remaining_seconds, 535);
    CHECK(!relay_report_due(&last, &now, 5000));
    CHECK(relay_report_due(&last, &now, RELAY_HEARTBEAT_MS));

    capsule_apply(CAPSULE_ACT_PAUSE);
    now.state = state();
    CHECK(relay_report_due(&last, &now, 5000));  // running changed

    last = now;
    capsule_apply(CAPSULE_ACT_RESET);  // still paused, but back at the full time
    now.state = state();
    CHECK_INT(now.state.remaining_seconds, 540);
    CHECK(relay_report_due(&last, &now, 5000));

    capsule_set_timer("Short", 2, true);
    last.state = state();
    stub_advance_ms(2000);
    now.state = state();
    CHECK(now.state.done);
    CHECK(relay_report_due(&last, &now, 2000));  // the end of the timer is reported at once
}

// ---- what to do after a request ----

static relay_schedule_t s_schedule;

static relay_verdict_t after(relay_step_t step, relay_outcome_t outcome, int64_t now)
{
    return relay_after_request(&s_schedule, step, outcome, now);
}

static void test_after_a_poll_that_works(void)
{
    s_schedule = (relay_schedule_t){ 0 };
    relay_verdict_t verdict = after(RELAY_STEP_POLL, RELAY_OUTCOME_OK, 1000);
    CHECK(!verdict.forget && !verdict.offline && !verdict.recovered);
    CHECK_INT(verdict.wait_ms, 0);
    CHECK_INT(s_schedule.failures, 0);
    CHECK_INT(s_schedule.wait_until, 0);
}

static void test_after_failures_back_off_and_go_offline(void)
{
    static const uint32_t waits[] = { 2000, 4000, 8000, 16000, 30000, 30000 };
    s_schedule = (relay_schedule_t){ 0 };
    int64_t now = 5000;
    for (unsigned i = 0; i < sizeof(waits) / sizeof(waits[0]); i++) {
        relay_step_t step = i % 2 ? RELAY_STEP_REGISTER : RELAY_STEP_POLL;  // either kind counts
        relay_verdict_t verdict = after(step, RELAY_OUTCOME_FAILED, now);
        CHECK_INT(verdict.wait_ms, waits[i]);
        CHECK_INT(s_schedule.wait_until, now + waits[i]);
        CHECK_INT(s_schedule.failures, i + 1);
        CHECK_INT(verdict.offline, i + 1 >= RELAY_OFFLINE_AFTER);  // not on the first failure
        CHECK(!verdict.forget);  // "no answer" is no reason to throw the token away
        CHECK(!verdict.recovered);
        now = s_schedule.wait_until;
    }
    relay_verdict_t verdict = after(RELAY_STEP_POLL, RELAY_OUTCOME_OK, now);
    CHECK(verdict.recovered && !verdict.offline && !verdict.forget);
    CHECK_INT(verdict.wait_ms, 0);
    CHECK_INT(s_schedule.failures, 0);

    // One failure and back: the screen never said "offline", so nothing "recovers".
    after(RELAY_STEP_POLL, RELAY_OUTCOME_FAILED, now);
    CHECK(!after(RELAY_STEP_POLL, RELAY_OUTCOME_OK, now + 2000).recovered);
}

static void test_after_401_forgets_and_backs_off(void)
{
    s_schedule = (relay_schedule_t){ 0 };
    relay_verdict_t verdict = after(RELAY_STEP_POLL, RELAY_OUTCOME_UNAUTHORIZED, 1000);
    CHECK(verdict.forget);
    CHECK(!verdict.offline);  // the relay was restarted, say: one 401, one registration, and on
    CHECK_INT(verdict.wait_ms, 2000);
    CHECK_INT(s_schedule.wait_until, 3000);  // the registration waits too
    CHECK_INT(s_schedule.failures, 1);
}

static void test_a_relay_that_registers_but_refuses_the_token_does_not_spin(void)
{
    // 201 to every registration, 401 to every poll. The registration must not end the
    // backoff, or the board would register about twice a second for ever.
    static const uint32_t waits[] = { 2000, 4000, 8000, 16000, 30000, 30000, 30000 };
    s_schedule = (relay_schedule_t){ 0 };
    int64_t now = 0;
    int registrations = 0;
    for (unsigned i = 0; i < sizeof(waits) / sizeof(waits[0]); i++) {
        relay_verdict_t verdict = after(RELAY_STEP_POLL, RELAY_OUTCOME_UNAUTHORIZED, now);
        CHECK(verdict.forget);
        CHECK_INT(verdict.wait_ms, waits[i]);
        CHECK_INT(verdict.offline, i >= 1);
        now = s_schedule.wait_until;
        verdict = after(RELAY_STEP_REGISTER, RELAY_OUTCOME_OK, now);
        registrations++;
        CHECK(!verdict.forget && !verdict.recovered);
        CHECK_INT(verdict.wait_ms, 0);
        CHECK_INT(s_schedule.failures, i + 1);   // still counting
        CHECK_INT(s_schedule.wait_until, now);   // the poll with the new token may go at once
    }
    CHECK_INT(registrations, 7);
    CHECK_INT(now, 120000);  // seven registrations in two minutes, then one every 30 s
    // The first poll the relay accepts ends it.
    relay_verdict_t verdict = after(RELAY_STEP_POLL, RELAY_OUTCOME_OK, now);
    CHECK(verdict.recovered);
    CHECK_INT(s_schedule.failures, 0);
}

static void test_after_register_outcomes(void)
{
    s_schedule = (relay_schedule_t){ 0 };
    // Whatever a registration is refused with, there is no token to forget.
    relay_verdict_t verdict = after(RELAY_STEP_REGISTER, RELAY_OUTCOME_UNAUTHORIZED, 0);
    CHECK(!verdict.forget);
    CHECK_INT(verdict.wait_ms, 2000);
    verdict = after(RELAY_STEP_REGISTER, RELAY_OUTCOME_FAILED, 2000);
    CHECK(!verdict.forget && verdict.offline);
    CHECK_INT(verdict.wait_ms, 4000);
    // A first registration on a healthy relay: nothing to wait for.
    s_schedule = (relay_schedule_t){ 0 };
    verdict = after(RELAY_STEP_REGISTER, RELAY_OUTCOME_OK, 0);
    CHECK(!verdict.forget && !verdict.offline && !verdict.recovered);
    CHECK_INT(s_schedule.failures, 0);
    CHECK_INT(s_schedule.wait_until, 0);
}

static void test_a_failing_report_leaves_polling_alone(void)
{
    static const uint32_t waits[] = { 2000, 4000, 8000, 16000, 30000, 30000 };
    s_schedule = (relay_schedule_t){ 0 };
    int64_t now = 1000;
    for (unsigned i = 0; i < sizeof(waits) / sizeof(waits[0]); i++) {
        // Refused or unanswered, even with a 401: the poll decides whether the token is good.
        relay_outcome_t outcome = i % 2 ? RELAY_OUTCOME_UNAUTHORIZED : RELAY_OUTCOME_FAILED;
        relay_verdict_t verdict = after(RELAY_STEP_REPORT, outcome, now);
        CHECK(!verdict.forget && !verdict.offline && !verdict.recovered);
        CHECK_INT(verdict.wait_ms, 0);
        CHECK_INT(s_schedule.failures, 0);
        CHECK_INT(s_schedule.wait_until, 0);  // the next poll is not held up
        CHECK_INT(s_schedule.report_failures, i + 1);
        CHECK_INT(s_schedule.report_wait_until, now + waits[i]);  // the report itself is
        now = s_schedule.report_wait_until;
    }
    after(RELAY_STEP_POLL, RELAY_OUTCOME_OK, now);
    CHECK_INT(s_schedule.report_failures, 6);  // a good poll does not hurry the report either
    after(RELAY_STEP_REPORT, RELAY_OUTCOME_OK, now);
    CHECK_INT(s_schedule.report_failures, 0);

    // And the other way round: a report that works says nothing about failing polls.
    after(RELAY_STEP_POLL, RELAY_OUTCOME_FAILED, now);
    after(RELAY_STEP_POLL, RELAY_OUTCOME_FAILED, now);
    relay_verdict_t verdict = after(RELAY_STEP_REPORT, RELAY_OUTCOME_OK, now);
    CHECK(!verdict.recovered);
    CHECK_INT(s_schedule.failures, 2);
}

static void test_failures_do_not_wrap(void)
{
    s_schedule = (relay_schedule_t){ .failures = 4294967295u };
    relay_verdict_t verdict = after(RELAY_STEP_POLL, RELAY_OUTCOME_FAILED, 0);
    CHECK_INT(s_schedule.failures, 4294967295u);
    CHECK_INT(verdict.wait_ms, RELAY_BACKOFF_MAX_MS);
    CHECK(verdict.offline);
}

// ---- sizes ----

static void test_the_longest_answers_fit(void)
{
    // Every field at the limit the board accepts, and the label written the longest way a
    // server could (47 control characters, six bytes each as \u00XX).
    char id[RELAY_ID_MAX + 1], token[RELAY_TOKEN_MAX + 1], code[RELAY_CODE_MAX + 1], url[RELAY_PAIR_URL_MAX + 1];
    char label[47 * 6 + 1] = "";
    memset(id, 'i', RELAY_ID_MAX), id[RELAY_ID_MAX] = '\0';
    memset(token, 't', RELAY_TOKEN_MAX), token[RELAY_TOKEN_MAX] = '\0';
    memset(code, 'c', RELAY_CODE_MAX), code[RELAY_CODE_MAX] = '\0';
    memset(url, 'u', RELAY_PAIR_URL_MAX), url[RELAY_PAIR_URL_MAX] = '\0';
    for (int i = 0; i < 47; i++) {
        strcat(label, "\\u0001");
    }
    char body[2048];
    int len = snprintf(body, sizeof(body), "{\"id\":\"%s\",\"token\":\"%s\",\"code\":\"%s\",\"pair_url\":\"%s\"}", id, token,
                       code, url);
    CHECK(len < RELAY_MAX_RESPONSE - 200);
    relay_credentials_t got;
    CHECK(relay_parse_register(body, (size_t)len, &got));
    CHECK_INT(strlen(got.pair_url), RELAY_PAIR_URL_MAX);

    len = snprintf(body, sizeof(body),
                   "{\"claimed\":false,\"version\":9007199254740992,\"capsule\":{\"type\":\"counter\",\"label\":\"%s\","
                   "\"count\":999999,\"motion\":false},\"action_seq\":9007199254740992,\"action\":\"motion_off\","
                   "\"code\":\"%s\",\"pair_url\":\"%s\"}",
                   label, code, url);
    CHECK(len < RELAY_MAX_RESPONSE - 200);  // room for a field or two more
    fresh();
    relay_poll_t result = poll(body);
    CHECK(result.ok && result.capsule_applied);
    CHECK_INT(strlen(state().label), 47);
    CHECK_INT(strlen(result.pair_url), RELAY_PAIR_URL_MAX);
}

// ---- which capsule is on screen ----

static void test_setters_return_their_generation(void)
{
    uint32_t before = capsule_generation();
    CHECK_INT(capsule_set_counter("a", 1, false), before + 1);
    CHECK_INT(capsule_generation(), before + 1);
    CHECK_INT(capsule_set_timer("b", 5, false), before + 2);
    capsule_apply(CAPSULE_ACT_START);  // an action is not a new capsule
    CHECK_INT(capsule_generation(), before + 2);

    // The relay's capsule is remembered by the generation its own set produced.
    fresh();
    before = capsule_generation();
    poll(SQUATS(1, 0, "null"));
    CHECK_INT(s_sync.generation, before + 1);
    CHECK_INT(relay_shown_version(&s_sync), 1);
    capsule_set_counter("Local", 9, false);
    CHECK_INT(relay_shown_version(&s_sync), 0);
    // A refused capsule leaves both alone.
    uint32_t held = s_sync.generation;
    poll("{\"claimed\":true,\"version\":2,\"capsule\":{\"type\":\"timer\"},\"action_seq\":0}");
    CHECK_INT(s_sync.generation, held);
    CHECK_INT(capsule_generation(), before + 2);
}

// ---- backoff ----

static void test_backoff(void)
{
    static const uint32_t wanted[] = { 0, 2000, 4000, 8000, 16000, 30000, 30000, 30000 };
    for (unsigned failures = 0; failures < sizeof(wanted) / sizeof(wanted[0]); failures++) {
        CHECK_INT(relay_backoff_ms(failures), wanted[failures]);
    }
    CHECK_INT(relay_backoff_ms(1000), RELAY_BACKOFF_MAX_MS);
    CHECK_INT(relay_backoff_ms(4000000000u), RELAY_BACKOFF_MAX_MS);
}

int main(void)
{
    capsule_init();
    test_register_body();
    test_parse_register();
    test_register_lengths();
    test_text_ok();
    test_code_ok();
    test_pair_url();
    test_take_pairing();
    test_poll_code();
    test_poll_nothing_to_do();
    test_poll_applies_a_new_version_once();
    test_poll_timer();
    test_local_capsule_wins_until_the_next_version();
    test_poll_refused_capsule();
    test_poll_capsule_null_keeps_the_screen();
    test_poll_actions();
    test_poll_motion_without_a_sensor();
    test_first_poll_does_not_replay_an_old_action();
    test_poll_unusable_answers();
    test_poll_deep_nesting_is_refused_before_parsing();
    test_poll_large_versions();
    test_report_body();
    test_report_due();
    test_report_running_timer_is_not_posted_every_second();
    test_after_a_poll_that_works();
    test_after_failures_back_off_and_go_offline();
    test_after_401_forgets_and_backs_off();
    test_a_relay_that_registers_but_refuses_the_token_does_not_spin();
    test_after_register_outcomes();
    test_a_failing_report_leaves_polling_alone();
    test_failures_do_not_wrap();
    test_the_longest_answers_fit();
    test_setters_return_their_generation();
    test_backoff();
    return check_report("test_relay");
}

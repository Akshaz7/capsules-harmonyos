// What the cloud relay client decides, without any networking: reading the relay's answers,
// whether to apply a capsule or an action, when to report state, how long to back off.
// relay.c does the HTTP. No ESP-IDF calls in here: tests/ builds this file on the host.
// The contract is in RELAY.md.
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "cJSON.h"

#include "capsule.h"

#define RELAY_ID_MAX 64            // characters; [A-Za-z0-9_-], it goes into a URL path
#define RELAY_TOKEN_MAX 128        // characters; [A-Za-z0-9._~+/=-], it goes into a header
#define RELAY_CODE_MAX 32          // bytes of printable ASCII; the board only displays it
#define RELAY_PAIR_URL_MAX 200     // bytes of printable ASCII; the board draws it as a QR code
#define RELAY_MAX_RESPONSE 1024    // bytes of a response body; a longer one is a failure. The longest
                                   // answers within the limits above are 468 bytes (register) and 704 (poll).

#define RELAY_POLL_MS 2000         // GET .../capsule this often
#define RELAY_HEARTBEAT_MS 10000   // POST .../state at least this often
#define RELAY_MIN_POST_GAP_MS 1000 // and at most this often, however fast the state changes
#define RELAY_BACKOFF_FIRST_MS 2000
#define RELAY_BACKOFF_MAX_MS 30000
#define RELAY_OFFLINE_AFTER 2      // failures in a row before the screen says "cloud offline"

typedef struct {
    char id[RELAY_ID_MAX + 1];
    char token[RELAY_TOKEN_MAX + 1];
    // Kept in RAM only: the relay repeats them in every poll answer while the board is unclaimed.
    char code[RELAY_CODE_MAX + 1];          // pairing phrase, e.g. "brave-otter-lamp"
    char pair_url[RELAY_PAIR_URL_MAX + 1];  // what the QR code holds; empty: the relay gave none
} relay_credentials_t;

// The body for POST /api/devices/register. Free with cJSON_free(). NULL if memory ran out.
char *relay_register_body(const char *hw, const char *fw);

// The 201 answer to it. `body[len]` must be a NUL. False (and *out untouched) unless id,
// token and code are all there and well-formed. pair_url is optional: one that is missing
// or cannot be shown comes back empty, and the board then shows the phrase alone.
bool relay_parse_register(const char *body, size_t len, relay_credentials_t *out);

// True if `text` is 1..max characters, all letters, digits or one of `extra`.
bool relay_text_ok(const char *text, size_t max, const char *extra);

// True if `text` is 1..max printable ASCII characters: something the board can display.
bool relay_printable(const char *text, size_t max);

// What has been taken from the relay so far. Start with relay_sync_reset() at boot and
// after every registration.
typedef struct {
    bool synced;          // a poll has been handled since the reset
    int64_t version;      // capsule version last taken from the relay (applied or refused); -1: none
    int64_t action_seq;   // action last taken from the relay (applied or not applicable)
    int64_t shown;        // version of the relay capsule last applied; 0: none
    uint32_t generation;  // the generation that capsule got when it was set (capsule.h)
} relay_sync_t;

void relay_sync_reset(relay_sync_t *sync);

typedef struct {
    bool ok;                    // false: the body was not a usable answer; nothing was changed
    bool claimed;
    char code[RELAY_CODE_MAX + 1];          // the pairing code in the answer; empty: none given
    char pair_url[RELAY_PAIR_URL_MAX + 1];  // and the URL that goes with it; empty: none given
    bool capsule_applied;
    const char *capsule_error;  // not NULL: a new version arrived and its capsule was refused
    bool action_applied;
    bool action_skipped;        // a new action arrived that is unknown or does not fit the capsule
} relay_poll_t;

// Handles the answer to GET /api/devices/{id}/capsule: applies the capsule if its version is
// not the one last taken, then the action if its action_seq is new. The first poll after a
// reset takes the capsule but only notes the action_seq: an action from before the board
// (re)started must not run a second time. `body[len]` must be a NUL.
relay_poll_t relay_handle_poll(relay_sync_t *sync, const char *body, size_t len);

// Takes over the pairing code (and the URL that goes with it) from a poll answer, for a
// relay that renews a code that ran out, and for a board that restarted (the code is not
// kept in flash). True if `credentials` changed. A new code without a URL clears the old
// URL: it belonged to the old code.
bool relay_take_pairing(relay_credentials_t *credentials, const relay_poll_t *poll);

// The relay version of the capsule on screen: 0 when the screen shows nothing from the
// relay (idle, or a capsule that was set over the local API since).
int64_t relay_shown_version(const relay_sync_t *sync);

typedef struct {
    capsule_state_t state;
    int64_t version;
} relay_report_t;

// The body for POST /api/devices/{id}/state: the GET /state object plus "version".
// Free with cJSON_free(). NULL if memory ran out.
char *relay_report_body(const relay_report_t *report);

// Whether to post `now`. `last` is the report last delivered (NULL: none yet) and
// `since_last_ms` the time since then. A change is posted soon, a running timer's
// remaining_seconds alone is not a change, and without changes there is a heartbeat.
bool relay_report_due(const relay_report_t *last, const relay_report_t *now, int64_t since_last_ms);

// ---- what to do after a request ----

typedef enum {
    RELAY_STEP_REGISTER,
    RELAY_STEP_POLL,
    RELAY_STEP_REPORT,
} relay_step_t;

typedef enum {
    RELAY_OUTCOME_OK,
    RELAY_OUTCOME_FAILED,        // no answer, an answer that makes no sense, or an unexpected status
    RELAY_OUTCOME_UNAUTHORIZED,  // 401: the relay does not know this device or token (any more)
} relay_outcome_t;

// Start with all zeroes.
typedef struct {
    unsigned failures;          // registrations and polls that failed in a row
    int64_t wait_until;         // nothing at all is sent before this time (ms)
    unsigned report_failures;   // state reports that failed in a row
    int64_t report_wait_until;  // no state report is sent before this time (ms)
} relay_schedule_t;

typedef struct {
    bool forget;       // drop the stored id and token; the next request is a registration
    bool offline;      // show "cloud offline"
    bool recovered;    // the relay answers again after having been shown as offline
    uint32_t wait_ms;  // how long registration and polling now pause; 0: they carry on
} relay_verdict_t;

// Updates `schedule` after a request made at about `now` (ms) and says what else to do.
// - Every failed registration or poll, a 401 included, lengthens the backoff.
// - Only a 401 to a poll forgets the registration, and the new registration waits for the
//   backoff like anything else. A 404 is a failure like any other.
// - Only a poll that succeeds ends the backoff; a registration that succeeds does not.
// - A state report never changes when the next poll happens or what the screen says.
relay_verdict_t relay_after_request(relay_schedule_t *schedule, relay_step_t step, relay_outcome_t outcome,
                                    int64_t now);

// How long to wait after `failures` failed requests in a row (0 for none).
uint32_t relay_backoff_ms(unsigned failures);

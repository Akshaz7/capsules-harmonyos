// Cloud relay client: registers the board with the backend, shows a pairing QR code and phrase, then
// polls for capsules and actions and reports state. Outbound requests only. See RELAY.md.
// Switched off (nothing is started) when RELAY_URL in secrets.h is empty or missing.
#pragma once

typedef enum {
    RELAY_DISABLED,   // no RELAY_URL
    RELAY_STARTING,   // nothing heard from the relay yet
    RELAY_UNCLAIMED,  // registered; `code` is the pairing code to show
    RELAY_CLAIMED,    // a user has claimed the board
    RELAY_OFFLINE,    // the relay does not answer
} relay_state_t;

typedef struct {
    relay_state_t state;
    char code[33];       // the pairing phrase while unclaimed ("brave-otter-lamp"), else empty
    char pair_url[201];  // what to show as a QR code next to it; empty: the relay gave none
} relay_status_t;

// Call once, after net_start(). Returns at once; the work happens on its own task.
void relay_start(void);
void relay_get_status(relay_status_t *out);

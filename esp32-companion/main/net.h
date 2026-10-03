// Wi-Fi station: joins the first reachable network from secrets.h, keeps retrying
// forever, advertises harmoniser.local and reports where it is.
#pragma once

typedef enum {
    NET_UNCONFIGURED,  // no networks in secrets.h
    NET_OFFLINE,       // none of the networks is in range (still scanning)
    NET_JOINING,       // trying `ssid`
    NET_CONNECTED,     // `ip` on `ssid`
} net_state_t;

typedef struct {
    net_state_t state;
    char ssid[33];
    char ip[16];
} net_status_t;

void net_start(void);
void net_get_status(net_status_t *out);

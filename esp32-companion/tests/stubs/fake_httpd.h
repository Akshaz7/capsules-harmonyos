// Test side of the HTTP server stand-in.
#pragma once

#include "esp_http_server.h"

extern httpd_config_t fake_httpd_config;  // what http_api_start() asked for

// Runs one request through the registered handlers, the way the real server routes it:
// unknown path -> the 404 handler, known path with another method -> the 405 handler.
// claimed_len is the Content-Length; body_len is how much of it actually arrives.
typedef struct {
    esp_err_t result;  // what the handler returned: ESP_FAIL makes the real server close the socket
    int status;
    httpd_req_t req;   // response and content type are in here
} fake_exchange_t;

fake_exchange_t fake_request(httpd_method_t method, const char *uri, const char *body, size_t body_len,
                             size_t claimed_len);

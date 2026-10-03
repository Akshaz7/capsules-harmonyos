// Host stand-in for ESP-IDF's HTTP server: main/http_api.c registers its handlers here and
// the tests call them through fake_request() (fake_httpd.h). No sockets involved.
#pragma once

#include <stdbool.h>
#include <stddef.h>

#include "esp_err.h"

#define FAKE_RESPONSE_MAX 4096

typedef struct httpd_req {
    size_t content_len;
    // The rest exists only in this stand-in.
    const char *body;         // what httpd_req_recv() hands out
    size_t body_len;          // may be shorter than content_len: the client stalls
    size_t body_read;
    char status[48];
    char type[32];
    char response[FAKE_RESPONSE_MAX];
    size_t response_len;
    bool response_complete;
} httpd_req_t;

typedef enum {
    HTTP_GET,
    HTTP_POST,
    HTTP_PUT,
    HTTP_HEAD,
    HTTP_OPTIONS,
} httpd_method_t;

typedef enum {
    HTTPD_404_NOT_FOUND,
    HTTPD_405_METHOD_NOT_ALLOWED,
    HTTPD_ERR_CODE_MAX,
} httpd_err_code_t;

typedef void *httpd_handle_t;
typedef esp_err_t (*httpd_err_handler_func_t)(httpd_req_t *req, httpd_err_code_t error);

typedef struct {
    const char *uri;
    httpd_method_t method;
    esp_err_t (*handler)(httpd_req_t *req);
} httpd_uri_t;

typedef struct {
    int server_port;
    int stack_size;
    bool lru_purge_enable;
    int recv_wait_timeout;
} httpd_config_t;

#define HTTPD_DEFAULT_CONFIG() { .recv_wait_timeout = 5 }

esp_err_t httpd_start(httpd_handle_t *handle, const httpd_config_t *config);
esp_err_t httpd_register_uri_handler(httpd_handle_t handle, const httpd_uri_t *uri);
esp_err_t httpd_register_err_handler(httpd_handle_t handle, httpd_err_code_t error, httpd_err_handler_func_t handler);

int httpd_req_recv(httpd_req_t *req, char *buf, size_t len);
esp_err_t httpd_resp_set_status(httpd_req_t *req, const char *status);
esp_err_t httpd_resp_set_type(httpd_req_t *req, const char *type);
esp_err_t httpd_resp_sendstr(httpd_req_t *req, const char *text);
esp_err_t httpd_resp_send_chunk(httpd_req_t *req, const char *data, size_t len);
esp_err_t httpd_resp_send_500(httpd_req_t *req);

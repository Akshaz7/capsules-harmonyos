#include "fake_httpd.h"

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_ROUTES 8

httpd_config_t fake_httpd_config;
static const httpd_uri_t *s_routes[MAX_ROUTES];
static int s_route_count;
static httpd_err_handler_func_t s_err_handlers[HTTPD_ERR_CODE_MAX];
static int s_server;

esp_err_t httpd_start(httpd_handle_t *handle, const httpd_config_t *config)
{
    fake_httpd_config = *config;
    s_route_count = 0;
    *handle = &s_server;
    return ESP_OK;
}

esp_err_t httpd_register_uri_handler(httpd_handle_t handle, const httpd_uri_t *uri)
{
    assert(handle == &s_server && s_route_count < MAX_ROUTES);
    s_routes[s_route_count++] = uri;
    return ESP_OK;
}

esp_err_t httpd_register_err_handler(httpd_handle_t handle, httpd_err_code_t error, httpd_err_handler_func_t handler)
{
    assert(handle == &s_server && error < HTTPD_ERR_CODE_MAX);
    s_err_handlers[error] = handler;
    return ESP_OK;
}

int httpd_req_recv(httpd_req_t *req, char *buf, size_t len)
{
    size_t left = req->body_len - req->body_read;
    if (left == 0) {
        return -1;  // nothing more is coming: the real server reports a timeout
    }
    size_t n = len < left ? len : left;
    if (n > 100) {
        n = 100;  // arrive in pieces, as a body spread over several TCP segments does
    }
    memcpy(buf, req->body + req->body_read, n);
    req->body_read += n;
    return (int)n;
}

esp_err_t httpd_resp_set_status(httpd_req_t *req, const char *status)
{
    snprintf(req->status, sizeof(req->status), "%s", status);
    return ESP_OK;
}

esp_err_t httpd_resp_set_type(httpd_req_t *req, const char *type)
{
    snprintf(req->type, sizeof(req->type), "%s", type);
    return ESP_OK;
}

esp_err_t httpd_resp_send_chunk(httpd_req_t *req, const char *data, size_t len)
{
    assert(!req->response_complete);
    if (!data) {
        req->response_complete = true;
        return ESP_OK;
    }
    assert(req->response_len + len < FAKE_RESPONSE_MAX);
    memcpy(req->response + req->response_len, data, len);
    req->response_len += len;
    req->response[req->response_len] = '\0';
    return ESP_OK;
}

esp_err_t httpd_resp_sendstr(httpd_req_t *req, const char *text)
{
    assert(req->response_len == 0);  // one answer per request
    httpd_resp_send_chunk(req, text, strlen(text));
    req->response_complete = true;
    return ESP_OK;
}

esp_err_t httpd_resp_send_500(httpd_req_t *req)
{
    httpd_resp_set_status(req, "500 Internal Server Error");
    return httpd_resp_sendstr(req, "");
}

fake_exchange_t fake_request(httpd_method_t method, const char *uri, const char *body, size_t body_len,
                             size_t claimed_len)
{
    fake_exchange_t exchange = { .req = { .content_len = claimed_len, .body = body, .body_len = body_len } };
    snprintf(exchange.req.status, sizeof(exchange.req.status), "200 OK");  // the real server's default
    bool path_known = false;
    const httpd_uri_t *route = NULL;
    for (int i = 0; i < s_route_count; i++) {
        if (strcmp(s_routes[i]->uri, uri) == 0) {
            path_known = true;
            if (s_routes[i]->method == method) {
                route = s_routes[i];
            }
        }
    }
    if (route) {
        exchange.result = route->handler(&exchange.req);
    } else {
        httpd_err_code_t error = path_known ? HTTPD_405_METHOD_NOT_ALLOWED : HTTPD_404_NOT_FOUND;
        assert(s_err_handlers[error]);
        exchange.result = s_err_handlers[error](&exchange.req, error);
    }
    assert(exchange.req.response_complete);  // every request gets an answer
    exchange.status = atoi(exchange.req.status);
    return exchange;
}

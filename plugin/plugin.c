#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "resource.h"

/* CLIProxyAPI's documented stable C ABI, version 1. No host callbacks are used. */
typedef struct { void *ptr; size_t len; } cliproxy_buffer;
typedef int (*host_call_fn)(void *, const char *, const uint8_t *, size_t, cliproxy_buffer *);
typedef void (*host_free_fn)(void *, size_t);
typedef struct {
    uint32_t abi_version;
    void *host_ctx;
    host_call_fn call;
    host_free_fn free_buffer;
} cliproxy_host_api;
typedef int (*plugin_call_fn)(const char *, const uint8_t *, size_t, cliproxy_buffer *);
typedef struct {
    uint32_t abi_version;
    plugin_call_fn call;
    void (*free_buffer)(void *, size_t);
    void (*shutdown)(void);
} cliproxy_plugin_api;

static int respond(cliproxy_buffer *out, const char *json) {
    if (!out) return 1;
    out->ptr = NULL; out->len = 0;
    const size_t len = strlen(json);
    void *ptr = malloc(len);
    if (!ptr) return 1;
    memcpy(ptr, json, len);
    out->ptr = ptr; out->len = len;
    return 0;
}

static int invoke(const char *method, const uint8_t *request, size_t len, cliproxy_buffer *out) {
    (void)request; (void)len;
    if (!method) return respond(out, "{\"ok\":false,\"error\":{\"code\":\"invalid_method\",\"message\":\"Method required\"}}");
    if (!strcmp(method, "plugin.register") || !strcmp(method, "plugin.reconfigure")) {
        return respond(out, "{\"ok\":true,\"result\":{\"schema_version\":6,\"metadata\":{\"Name\":\"CPAMC Menu Bar\",\"Version\":\"0.1.0\",\"Author\":\"Florian Pariset\",\"GitHubRepository\":\"https://github.com/mindtheflo/cpamc-menubar\",\"ConfigFields\":[]},\"capabilities\":{\"management_api\":true}}}");
    }
    if (!strcmp(method, "management.register")) {
        return respond(out, "{\"ok\":true,\"result\":{\"resources\":[{\"Path\":\"/menubar\",\"Menu\":\"Menu Bar · Made for Notis\",\"Description\":\"Claude and Codex subscriptions in your macOS menu bar.\"}]}}");
    }
    if (!strcmp(method, "management.handle")) return respond(out, CPAMC_RESOURCE_RESPONSE);
    return respond(out, "{\"ok\":false,\"error\":{\"code\":\"unknown_method\",\"message\":\"Unsupported method\"}}");
}
static void release_buffer(void *ptr, size_t len) { (void)len; free(ptr); }
static void shutdown_plugin(void) {}

__attribute__((visibility("default")))
int cliproxy_plugin_init(const cliproxy_host_api *host, cliproxy_plugin_api *plugin) {
    if (!host || host->abi_version != 1 || !plugin) return 1;
    plugin->abi_version = 1;
    plugin->call = invoke;
    plugin->free_buffer = release_buffer;
    plugin->shutdown = shutdown_plugin;
    return 0;
}

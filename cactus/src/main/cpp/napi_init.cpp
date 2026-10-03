// Node-API wrapper around the Cactus C FFI.
//   initModel(path: string): Promise<boolean>
//   complete(prompt: string, system?: string, maxTokens?: number, toolsJson?: string, imagePath?: string): Promise<string>
//       toolsJson: OpenAI-style tools array; when given, force_tools is on (output constrained to a tool call)
//       imagePath: an image file the app can read (jpg/png); passed to vision models (LFM2-VL) with the prompt
//       (resolves to the raw Cactus response JSON)
//   freeModel(): void
// initModel and complete run on the libuv worker pool via napi_async_work.
#include <chrono>
#include <cstdio>
#include <mutex>
#include <string>
#include <vector>

#include <hilog/log.h>
#include "napi/native_api.h"
#include "cactus_ffi.h"

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x0C70
#define LOG_TAG "CactusNapi"

namespace {

std::mutex g_mutex;              // serialises every call into the engine
cactus_model_t g_model = nullptr;

constexpr size_t kResponseBufferSize = 64 * 1024;
constexpr int32_t kDefaultMaxTokens = 128;

std::string GetString(napi_env env, napi_value value) {
    size_t len = 0;
    napi_get_value_string_utf8(env, value, nullptr, 0, &len);
    std::string out(len, '\0');
    napi_get_value_string_utf8(env, value, out.data(), len + 1, &len);
    return out;
}

std::string JsonEscape(const std::string& s) {
    std::string out;
    out.reserve(s.size() + 8);
    for (unsigned char c : s) {
        switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (c < 0x20) {
                    char buf[8];
                    snprintf(buf, sizeof(buf), "\\u%04x", c);
                    out += buf;
                } else {
                    out += static_cast<char>(c);
                }
        }
    }
    return out;
}

std::string ErrorJson(const std::string& msg) {
    return "{\"success\":false,\"error\":\"" + JsonEscape(msg) + "\"}";
}

// ---- initModel -------------------------------------------------------------

struct InitWork {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::string path;
    bool ok = false;
};

void InitExecute(napi_env, void* data) {
    auto* w = static_cast<InitWork*>(data);
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_model) {
        cactus_destroy(g_model);
        g_model = nullptr;
    }
    auto t0 = std::chrono::steady_clock::now();
    g_model = cactus_init(w->path.c_str(), nullptr, false);
    auto ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
    w->ok = g_model != nullptr;
    if (w->ok) {
        OH_LOG_INFO(LOG_APP, "cactus_init ok in %{public}.1f ms: %{public}s", ms, w->path.c_str());
    } else {
        const char* err = cactus_get_last_error();
        OH_LOG_ERROR(LOG_APP, "cactus_init failed: %{public}s", err ? err : "(null)");
    }
}

void InitComplete(napi_env env, napi_status, void* data) {
    auto* w = static_cast<InitWork*>(data);
    napi_value result;
    napi_get_boolean(env, w->ok, &result);
    napi_resolve_deferred(env, w->deferred, result);
    napi_delete_async_work(env, w->work);
    delete w;
}

napi_value InitModel(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) {
        napi_throw_type_error(env, nullptr, "initModel(path: string) requires a path");
        return nullptr;
    }
    auto* w = new InitWork();
    w->path = GetString(env, args[0]);
    napi_value promise;
    napi_create_promise(env, &w->deferred, &promise);
    napi_value name;
    napi_create_string_utf8(env, "cactusInit", NAPI_AUTO_LENGTH, &name);
    napi_create_async_work(env, nullptr, name, InitExecute, InitComplete, w, &w->work);
    napi_queue_async_work(env, w->work);
    return promise;
}

// ---- complete --------------------------------------------------------------

struct CompleteWork {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::string prompt;
    std::string system;
    int32_t maxTokens = kDefaultMaxTokens;
    std::string tools;
    std::string image;
    std::string result;
};

void CompleteExecute(napi_env, void* data) {
    auto* w = static_cast<CompleteWork*>(data);
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_model) {
        w->result = ErrorJson("model not initialised");
        return;
    }
    std::string messages = "[";
    if (!w->system.empty()) {
        messages += "{\"role\":\"system\",\"content\":\"" + JsonEscape(w->system) + "\"},";
    }
    messages += "{\"role\":\"user\",\"content\":\"" + JsonEscape(w->prompt) + "\"";
    if (!w->image.empty()) {
        messages += ",\"images\":[\"" + JsonEscape(w->image) + "\"]";
    }
    messages += "}]";
    std::string options = "{\"max_tokens\":" + std::to_string(w->maxTokens) +
                          ",\"temperature\":0.0,\"auto_handoff\":false" +
                          (w->tools.empty() ? std::string() : std::string(",\"force_tools\":true,\"tool_rag_top_k\":0")) +
                          "}";
    std::vector<char> buf(kResponseBufferSize, '\0');
    cactus_reset(g_model);  // stateless single-turn calls
    int rc = cactus_complete(g_model, messages.c_str(), buf.data(), buf.size(), options.c_str(),
                             w->tools.empty() ? nullptr : w->tools.c_str(), nullptr, nullptr, nullptr, 0);
    if (rc < 0) {
        const char* err = cactus_get_last_error();
        w->result = ErrorJson(std::string("cactus_complete rc=") + std::to_string(rc) + ": " +
                              (err ? err : "(null)"));
        OH_LOG_ERROR(LOG_APP, "%{public}s", w->result.c_str());
        return;
    }
    w->result.assign(buf.data());
    OH_LOG_INFO(LOG_APP, "cactus_complete: %{public}s", w->result.c_str());
}

void CompleteComplete(napi_env env, napi_status, void* data) {
    auto* w = static_cast<CompleteWork*>(data);
    napi_value result;
    napi_create_string_utf8(env, w->result.c_str(), w->result.size(), &result);
    napi_resolve_deferred(env, w->deferred, result);
    napi_delete_async_work(env, w->work);
    delete w;
}

napi_value Complete(napi_env env, napi_callback_info info) {
    size_t argc = 5;
    napi_value args[5] = {nullptr, nullptr, nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) {
        napi_throw_type_error(env, nullptr, "complete(prompt: string) requires a prompt");
        return nullptr;
    }
    auto* w = new CompleteWork();
    w->prompt = GetString(env, args[0]);
    napi_valuetype type = napi_undefined;
    if (argc >= 2 && napi_typeof(env, args[1], &type) == napi_ok && type == napi_string) {
        w->system = GetString(env, args[1]);
    }
    if (argc >= 3 && napi_typeof(env, args[2], &type) == napi_ok && type == napi_number) {
        napi_get_value_int32(env, args[2], &w->maxTokens);
        if (w->maxTokens <= 0) w->maxTokens = kDefaultMaxTokens;
    }
    if (argc >= 4 && napi_typeof(env, args[3], &type) == napi_ok && type == napi_string) {
        w->tools = GetString(env, args[3]);
    }
    if (argc >= 5 && napi_typeof(env, args[4], &type) == napi_ok && type == napi_string) {
        w->image = GetString(env, args[4]);
    }
    napi_value promise;
    napi_create_promise(env, &w->deferred, &promise);
    napi_value name;
    napi_create_string_utf8(env, "cactusComplete", NAPI_AUTO_LENGTH, &name);
    napi_create_async_work(env, nullptr, name, CompleteExecute, CompleteComplete, w, &w->work);
    napi_queue_async_work(env, w->work);
    return promise;
}

// ---- freeModel -------------------------------------------------------------

napi_value FreeModel(napi_env env, napi_callback_info) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_model) {
        cactus_destroy(g_model);
        g_model = nullptr;
    }
    return nullptr;
}

}  // namespace

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"initModel", nullptr, InitModel, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"complete", nullptr, Complete, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"freeModel", nullptr, FreeModel, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module cactusModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "cactus_napi",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterCactusModule(void) {
    napi_module_register(&cactusModule);
}

// Minimal subset of cactus-engine/cactus_engine.h (Cactus v2.2.2), copied verbatim
// so the wrapper does not pull in cactus_graph.h / cactus_kernels.h internals.
#ifndef CACTUS_FFI_SUBSET_H
#define CACTUS_FFI_SUBSET_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void* cactus_model_t;
typedef void (*cactus_token_callback)(const char* token, uint32_t token_id, void* user_data);

cactus_model_t cactus_init(const char* model_path, const char* corpus_dir, bool cache_index);
void cactus_destroy(cactus_model_t model);
void cactus_reset(cactus_model_t model);
int cactus_complete(cactus_model_t model, const char* messages_json, char* response_buffer,
                    size_t buffer_size, const char* options_json, const char* tools_json,
                    cactus_token_callback callback, void* user_data,
                    const uint8_t* pcm_buffer, size_t pcm_buffer_size);
const char* cactus_get_last_error(void);
void cactus_log_set_level(int level);

#ifdef __cplusplus
}
#endif

#endif

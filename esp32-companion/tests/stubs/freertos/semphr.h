// Host stand-in: a "mutex" that only checks it is taken and given in pairs.
#pragma once

#include <assert.h>

#include "stubs.h"

typedef struct {
    int unused;
} StaticSemaphore_t;
typedef StaticSemaphore_t *SemaphoreHandle_t;

static inline SemaphoreHandle_t xSemaphoreCreateMutexStatic(StaticSemaphore_t *storage)
{
    return storage;
}

static inline int xSemaphoreTake(SemaphoreHandle_t lock, unsigned ticks)
{
    (void)ticks;
    assert(lock && stub_lock_depth == 0);  // capsule_init() was called; no nested take
    stub_lock_depth++;
    return 1;
}

static inline int xSemaphoreGive(SemaphoreHandle_t lock)
{
    assert(lock && stub_lock_depth == 1);
    stub_lock_depth--;
    return 1;
}

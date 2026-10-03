// The whole test framework: CHECK() reports a failed condition and carries on, so one run
// shows every failure. End main() with `return check_report("name");`.
#pragma once

#include <stdio.h>
#include <string.h>

static int check_count;
static int check_failures;

#define CHECK(cond)                                                    \
    do {                                                               \
        check_count++;                                                 \
        if (!(cond)) {                                                 \
            check_failures++;                                          \
            printf("  FAIL  %s:%d  %s\n", __FILE__, __LINE__, #cond);  \
        }                                                              \
    } while (0)

#define CHECK_INT(actual, wanted)                                                                     \
    do {                                                                                              \
        long long check_a = (actual), check_w = (wanted);                                             \
        check_count++;                                                                                \
        if (check_a != check_w) {                                                                     \
            check_failures++;                                                                         \
            printf("  FAIL  %s:%d  %s is %lld, wanted %lld\n", __FILE__, __LINE__, #actual, check_a, check_w); \
        }                                                                                             \
    } while (0)

#define CHECK_STR(actual, wanted)                                                                       \
    do {                                                                                                \
        const char *check_a = (actual), *check_w = (wanted);                                            \
        check_count++;                                                                                  \
        if (strcmp(check_a, check_w) != 0) {                                                            \
            check_failures++;                                                                           \
            printf("  FAIL  %s:%d  %s is \"%s\", wanted \"%s\"\n", __FILE__, __LINE__, #actual, check_a, check_w); \
        }                                                                                               \
    } while (0)

static inline int check_report(const char *name)
{
    printf("%-18s %d checks, %d failed\n", name, check_count, check_failures);
    return check_failures ? 1 : 0;
}

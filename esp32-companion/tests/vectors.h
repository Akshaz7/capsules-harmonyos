// Readers for the vector files in tests/vectors/, shared by the C tests.
#pragma once

#include <ctype.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define VECTOR_LINE_MAX 4096

// Next line that is neither empty nor a comment, without its newline. False at the end.
static inline bool vector_next_line(FILE *file, char *line)
{
    while (fgets(line, VECTOR_LINE_MAX, file)) {
        line[strcspn(line, "\n")] = '\0';
        if (line[0] != '\0' && line[0] != '#') {
            return true;
        }
    }
    return false;
}

static inline FILE *vector_open(const char *path)
{
    FILE *file = fopen(path, "r");
    if (!file) {
        perror(path);
        exit(2);
    }
    return file;
}

// "61*3 c3a9" -> the bytes 61 61 61 c3 a9. "-" and spaces give nothing. Returns the length;
// out gets a terminator as well. Exits on a malformed vector: that is a bug in the file.
static inline size_t vector_bytes(const char *text, char *out, size_t out_size)
{
    size_t len = 0;
    const char *p = text;
    while (*p) {
        if (*p == ' ' || *p == '-') {
            p++;
            continue;
        }
        const char *start = p;
        while (isxdigit((unsigned char)*p)) {
            p++;
        }
        size_t digits = (size_t)(p - start);
        long repeat = *p == '*' ? strtol(p + 1, (char **)&p, 10) : 1;
        if (digits == 0 || digits % 2 != 0 || repeat < 1 || len + repeat * digits / 2 >= out_size) {
            fprintf(stderr, "bad vector: %s\n", text);
            exit(2);
        }
        for (long r = 0; r < repeat; r++) {
            for (size_t i = 0; i < digits; i += 2) {
                char pair[3] = { start[i], start[i + 1], '\0' };
                out[len++] = (char)strtol(pair, NULL, 16);
            }
        }
    }
    out[len] = '\0';
    return len;
}

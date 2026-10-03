// Host tests for main/validate.c: the JSON nesting/NUL scan and the UTF-8 check.
#include <stdbool.h>

#include "check.h"
#include "validate.h"
#include "vectors.h"

#define MAX_DEPTH 8

static const char *scan_name(json_scan_t result)
{
    switch (result) {
    case JSON_SCAN_OK:
        return "ok";
    case JSON_SCAN_TOO_DEEP:
        return "deep";
    default:
        return "nul";
    }
}

static void test_scan_vectors(const char *path)
{
    FILE *file = vector_open(path);
    char line[VECTOR_LINE_MAX], bytes[VECTOR_LINE_MAX];
    int vectors = 0;
    while (vector_next_line(file, line)) {
        char *tab = strchr(line, '\t');
        if (!tab) {
            fprintf(stderr, "bad vector: %s\n", line);
            exit(2);
        }
        *tab = '\0';
        const char *body = tab + 1;
        size_t len = strlen(body);
        if (strncmp(body, "hex:", 4) == 0) {
            len = vector_bytes(body + 4, bytes, sizeof(bytes));
            body = bytes;
        }
        const char *got = scan_name(json_scan(body, len, MAX_DEPTH));
        check_count++;
        if (strcmp(got, line) != 0) {
            check_failures++;
            printf("  FAIL  json_scan gives %s, wanted %s, for: %s\n", got, line, tab + 1);
        }
        vectors++;
    }
    fclose(file);
    CHECK(vectors >= 30);  // the file was really read
}

static void fill(char *buffer, size_t count, char c)
{
    memset(buffer, c, count);
    buffer[count] = '\0';
}

static void test_scan_long_bodies(void)
{
    char body[1100];
    // What crashed the board: 300 levels, and a full 1024-byte body of them.
    fill(body, 300, '[');
    CHECK(json_scan(body, 300, MAX_DEPTH) == JSON_SCAN_TOO_DEEP);
    fill(body, 1024, '{');
    CHECK(json_scan(body, 1024, MAX_DEPTH) == JSON_SCAN_TOO_DEEP);
    // The same brackets inside a string are just a long label.
    fill(body, 1024, '[');
    body[0] = '"';
    body[1023] = '"';
    CHECK(json_scan(body, 1024, MAX_DEPTH) == JSON_SCAN_OK);
    // 1000 arrays one after the other never go deeper than 1.
    for (int i = 0; i < 500; i++) {
        memcpy(body + 2 * i, "[]", 2);
    }
    CHECK(json_scan(body, 1000, MAX_DEPTH) == JSON_SCAN_OK);
}

static void test_scan_respects_length_and_limit(void)
{
    // Only len bytes are looked at: the buffer need not be terminated.
    const char nine[] = { '[', '[', '[', '[', '[', '[', '[', '[', '[' };
    CHECK(json_scan(nine, 8, MAX_DEPTH) == JSON_SCAN_OK);
    CHECK(json_scan(nine, 9, MAX_DEPTH) == JSON_SCAN_TOO_DEEP);
    CHECK(json_scan(nine, 0, MAX_DEPTH) == JSON_SCAN_OK);
    // A backslash as the very last byte must not make the scan read on.
    const char open_escape[] = { '"', '\\' };
    CHECK(json_scan(open_escape, 2, MAX_DEPTH) == JSON_SCAN_OK);
    const char short_escape[] = { '"', '\\', 'u', '0', '0', '0' };
    CHECK(json_scan(short_escape, 6, MAX_DEPTH) == JSON_SCAN_OK);
    const char full_escape[] = { '"', '\\', 'u', '0', '0', '0', '0' };
    CHECK(json_scan(full_escape, 7, MAX_DEPTH) == JSON_SCAN_HAS_NUL);
    // The limit is a parameter.
    CHECK(json_scan("[[", 2, 1) == JSON_SCAN_TOO_DEEP);
    CHECK(json_scan("[[", 2, 2) == JSON_SCAN_OK);
    CHECK(json_scan("{}", 2, 0) == JSON_SCAN_TOO_DEEP);
}

static void test_utf8_vectors(const char *path)
{
    FILE *file = vector_open(path);
    char line[VECTOR_LINE_MAX], label[VECTOR_LINE_MAX];
    int vectors = 0;
    while (vector_next_line(file, line)) {
        char *input = strchr(line, '|');
        char *stored = input ? strchr(input + 1, '|') : NULL;
        if (!stored) {
            fprintf(stderr, "bad vector: %s\n", line);
            exit(2);
        }
        *stored = '\0';
        vector_bytes(input + 1, label, sizeof(label));
        bool wanted = line[0] == '1';
        check_count++;
        if (utf8_valid(label) != wanted) {
            check_failures++;
            printf("  FAIL  utf8_valid is %d, wanted %d, for:%s\n", !wanted, wanted, input + 1);
        }
        vectors++;
    }
    fclose(file);
    CHECK(vectors >= 40);
}

int main(int argc, char **argv)
{
    if (argc != 3) {
        fprintf(stderr, "usage: %s json_scan.txt labels.txt\n", argv[0]);
        return 2;
    }
    test_scan_vectors(argv[1]);
    test_scan_long_bodies();
    test_scan_respects_length_and_limit();
    test_utf8_vectors(argv[2]);
    return check_report("test_validate");
}

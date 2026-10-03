// Host tests for main/capsule.c: the timer state machine, the counter and copy_label().
// capsule.c is included rather than linked so that the static copy_label() can be called.
// The clock and the lock come from tests/stubs/.
#include "../main/capsule.c"

#include "check.h"
#include "stubs.h"
#include "vectors.h"

#define T0 5000  // uptime in ms at which the tests create their capsules

static capsule_state_t get(void)
{
    capsule_state_t state;
    capsule_get(&state);
    CHECK_INT(stub_lock_depth, 0);
    return state;
}

static bool apply(capsule_action_t action)
{
    bool applied = capsule_apply(action);
    CHECK_INT(stub_lock_depth, 0);
    return applied;
}

// A running timer of `seconds`, started at T0.
static void start_timer(int seconds)
{
    stub_set_ms(T0);
    capsule_set_timer("t", seconds, true);
}

static void check_timer(capsule_state_t state, int remaining, bool running, bool done)
{
    CHECK_INT(state.type, CAPSULE_TIMER);
    CHECK_INT(state.remaining_seconds, remaining);
    CHECK_INT(state.running, running);
    CHECK_INT(state.done, done);
}

static void test_idle(void)
{
    capsule_state_t state = get();
    CHECK_INT(state.type, CAPSULE_IDLE);
    CHECK_STR(state.label, "");
    CHECK_INT(state.count + state.seconds + state.remaining_seconds, 0);
    CHECK(!state.running && !state.done && !state.motion);
    for (int action = CAPSULE_ACT_START; action <= CAPSULE_ACT_MOTION_OFF; action++) {
        CHECK(!apply(action));  // nothing applies while idle
    }
    capsule_count_rep();
    CHECK_INT(get().type, CAPSULE_IDLE);
    CHECK_STR(capsule_type_name(CAPSULE_IDLE), "idle");
    CHECK_STR(capsule_type_name(CAPSULE_TIMER), "timer");
    CHECK_STR(capsule_type_name(CAPSULE_COUNTER), "counter");
}

static void test_new_timer(void)
{
    start_timer(10);
    capsule_state_t state = get();
    check_timer(state, 10, true, false);
    CHECK_INT(state.seconds, 10);
    CHECK_STR(state.label, "t");

    stub_set_ms(T0);
    capsule_set_timer("paused", 10, false);
    stub_advance_ms(60000);
    check_timer(get(), 10, false, false);  // loaded paused: time does not touch it
}

// remaining_seconds is rounded up: it shows 1 until the very last millisecond is gone.
static void test_remaining_rounds_up(void)
{
    static const struct {
        int ms_left;
        int seconds_shown;
    } CASES[] = { { 10000, 10 }, { 9001, 10 }, { 9000, 9 }, { 1001, 2 }, { 1000, 1 }, { 999, 1 }, { 1, 1 } };
    for (size_t i = 0; i < sizeof(CASES) / sizeof(CASES[0]); i++) {
        // running
        start_timer(10);
        stub_set_ms(T0 + 10000 - CASES[i].ms_left);
        check_timer(get(), CASES[i].seconds_shown, true, false);
        // paused with the same time left, read much later
        CHECK(apply(CAPSULE_ACT_PAUSE));
        stub_advance_ms(3600000);
        check_timer(get(), CASES[i].seconds_shown, false, false);
    }
    // 0 ms left: that is the end.
    start_timer(10);
    stub_set_ms(T0 + 10000);
    check_timer(get(), 0, false, true);
}

static void test_done_is_set_exactly_at_the_deadline_and_stays(void)
{
    start_timer(2);
    stub_set_ms(T0 + 1999);
    check_timer(get(), 1, true, false);
    stub_set_ms(T0 + 2000);
    check_timer(get(), 0, false, true);
    // Reading again, or much later, changes nothing.
    check_timer(get(), 0, false, true);
    stub_advance_ms(1);
    check_timer(get(), 0, false, true);
    stub_advance_ms(86400000);
    check_timer(get(), 0, false, true);
    CHECK_INT(get().seconds, 2);

    // Noticed late (nobody read the state at the deadline): the same result.
    start_timer(2);
    stub_set_ms(T0 + 500000);
    check_timer(get(), 0, false, true);

    // After a reset it is not done, and the old deadline cannot make it done again.
    CHECK(apply(CAPSULE_ACT_RESET));
    check_timer(get(), 2, false, false);
    stub_advance_ms(86400000);
    check_timer(get(), 2, false, false);

    // A second run ends once, at its own deadline.
    int64_t restart = T0 + 500000 + 86400000;
    CHECK(apply(CAPSULE_ACT_START));
    stub_set_ms(restart + 1999);
    check_timer(get(), 1, true, false);
    stub_set_ms(restart + 2000);
    check_timer(get(), 0, false, true);
}

static void test_pause_at_the_deadline(void)
{
    // One millisecond before the end the pause still catches it...
    start_timer(10);
    stub_set_ms(T0 + 9999);
    CHECK(apply(CAPSULE_ACT_PAUSE));
    check_timer(get(), 1, false, false);
    stub_advance_ms(60000);
    check_timer(get(), 1, false, false);
    // ...and resuming runs that last millisecond.
    CHECK(apply(CAPSULE_ACT_START));
    check_timer(get(), 1, true, false);
    stub_advance_ms(1);
    check_timer(get(), 0, false, true);

    // At the deadline itself the timer has ended; the pause is accepted and changes nothing.
    start_timer(10);
    stub_set_ms(T0 + 10000);
    CHECK(apply(CAPSULE_ACT_PAUSE));
    check_timer(get(), 0, false, true);
    // "Resume" then means: run again from the top.
    CHECK(apply(CAPSULE_ACT_START));
    check_timer(get(), 10, true, false);
    stub_advance_ms(9999);
    check_timer(get(), 1, true, false);
    stub_advance_ms(1);
    check_timer(get(), 0, false, true);

    // The same with a tap (toggle) one millisecond before the end.
    start_timer(10);
    stub_set_ms(T0 + 9999);
    CHECK(apply(CAPSULE_ACT_TOGGLE));
    check_timer(get(), 1, false, false);
    CHECK(apply(CAPSULE_ACT_TOGGLE));
    stub_advance_ms(1);
    check_timer(get(), 0, false, true);
}

static void test_pause_and_resume(void)
{
    start_timer(10);
    stub_set_ms(T0 + 2500);
    CHECK(apply(CAPSULE_ACT_PAUSE));
    check_timer(get(), 8, false, false);
    CHECK(apply(CAPSULE_ACT_PAUSE));  // pausing twice is harmless
    stub_advance_ms(100000);
    check_timer(get(), 8, false, false);
    CHECK(apply(CAPSULE_ACT_START));
    CHECK(apply(CAPSULE_ACT_START));  // so is starting twice: the deadline does not move
    stub_advance_ms(7499);
    check_timer(get(), 1, true, false);
    stub_advance_ms(1);
    check_timer(get(), 0, false, true);
}

static void finish_timer(int seconds)
{
    start_timer(seconds);
    stub_set_ms(T0 + seconds * 1000 + 3000);
    check_timer(get(), 0, false, true);
}

static void test_actions_after_done(void)
{
    // start: from the top, running
    finish_timer(10);
    CHECK(apply(CAPSULE_ACT_START));
    check_timer(get(), 10, true, false);
    stub_advance_ms(10000);
    check_timer(get(), 0, false, true);

    // toggle (a tap): back to the full time, paused; the next tap runs it
    finish_timer(10);
    CHECK(apply(CAPSULE_ACT_TOGGLE));
    check_timer(get(), 10, false, false);
    CHECK(apply(CAPSULE_ACT_TOGGLE));
    check_timer(get(), 10, true, false);

    // reset: full time, paused
    finish_timer(10);
    CHECK(apply(CAPSULE_ACT_RESET));
    check_timer(get(), 10, false, false);

    // pause: accepted, still done
    finish_timer(10);
    CHECK(apply(CAPSULE_ACT_PAUSE));
    check_timer(get(), 0, false, true);

    // An action that arrives after the deadline, before anyone read the state, sees a
    // finished timer: the toggle resets it instead of pausing it.
    start_timer(10);
    stub_set_ms(T0 + 10000);
    CHECK(apply(CAPSULE_ACT_TOGGLE));
    check_timer(get(), 10, false, false);
}

static void test_reset_while_running(void)
{
    start_timer(10);
    stub_set_ms(T0 + 4000);
    check_timer(get(), 6, true, false);
    CHECK(apply(CAPSULE_ACT_RESET));
    check_timer(get(), 10, false, false);
    stub_set_ms(T0 + 20000);  // past the deadline it had
    check_timer(get(), 10, false, false);
    CHECK(apply(CAPSULE_ACT_START));
    stub_advance_ms(9999);
    check_timer(get(), 1, true, false);
    stub_advance_ms(1);
    check_timer(get(), 0, false, true);

    // reset while paused part-way
    start_timer(10);
    stub_set_ms(T0 + 4000);
    CHECK(apply(CAPSULE_ACT_PAUSE));
    CHECK(apply(CAPSULE_ACT_RESET));
    check_timer(get(), 10, false, false);
}

static void test_longest_timer(void)
{
    const int64_t length_ms = (int64_t)CAPSULE_MAX_SECONDS * 1000;  // does not fit in 32 bits
    start_timer(CAPSULE_MAX_SECONDS);
    capsule_state_t state = get();
    check_timer(state, CAPSULE_MAX_SECONDS, true, false);
    CHECK_INT(state.seconds, 359999);
    stub_set_ms(T0 + 1);
    check_timer(get(), 359999, true, false);
    stub_set_ms(T0 + 1000);
    check_timer(get(), 359998, true, false);
    stub_set_ms(T0 + length_ms - 1001);
    check_timer(get(), 2, true, false);
    stub_set_ms(T0 + length_ms - 1);
    check_timer(get(), 1, true, false);
    stub_set_ms(T0 + length_ms);
    check_timer(get(), 0, false, true);

    // Paused for longer than it runs, then run to the end.
    start_timer(CAPSULE_MAX_SECONDS);
    stub_set_ms(T0 + 500);
    CHECK(apply(CAPSULE_ACT_PAUSE));
    stub_advance_ms(2 * length_ms);
    check_timer(get(), 359999, false, false);
    CHECK(apply(CAPSULE_ACT_START));
    stub_advance_ms(length_ms - 501);
    check_timer(get(), 1, true, false);
    stub_advance_ms(1);
    check_timer(get(), 0, false, true);

    // On a board that has been up for a year.
    const int64_t year_ms = 365LL * 24 * 3600 * 1000;
    stub_set_ms(year_ms);
    capsule_set_timer("t", CAPSULE_MAX_SECONDS, true);
    stub_set_ms(year_ms + length_ms - 1);
    check_timer(get(), 1, true, false);
    stub_advance_ms(1);
    check_timer(get(), 0, false, true);
}

// Each operation reads the clock once, so "has it ended" and "how long is left" cannot
// disagree when the deadline passes in the middle of a call.
static void test_clock_is_read_once_per_operation(void)
{
    start_timer(10);
    int reads = stub_clock_reads;
    get();
    CHECK_INT(stub_clock_reads - reads, 1);
    reads = stub_clock_reads;
    apply(CAPSULE_ACT_PAUSE);
    CHECK_INT(stub_clock_reads - reads, 1);
    reads = stub_clock_reads;
    apply(CAPSULE_ACT_TOGGLE);
    CHECK_INT(stub_clock_reads - reads, 1);
    reads = stub_clock_reads;
    capsule_set_timer("t", 10, true);
    CHECK_INT(stub_clock_reads - reads, 1);
}

static void test_timer_rejects_counter_actions(void)
{
    start_timer(10);
    CHECK(!apply(CAPSULE_ACT_INCREMENT));
    CHECK(!apply(CAPSULE_ACT_MOTION_ON));
    CHECK(!apply(CAPSULE_ACT_MOTION_OFF));
    capsule_count_rep();
    capsule_state_t state = get();
    check_timer(state, 10, true, false);
    CHECK_INT(state.count, 0);
    CHECK(!state.motion);
}

static void test_counter(void)
{
    capsule_set_counter("Squats", 41, false);
    capsule_state_t state = get();
    CHECK_INT(state.type, CAPSULE_COUNTER);
    CHECK_STR(state.label, "Squats");
    CHECK_INT(state.count, 41);
    CHECK(!state.motion && !state.running && !state.done);
    CHECK_INT(state.seconds + state.remaining_seconds, 0);

    CHECK(apply(CAPSULE_ACT_INCREMENT));
    CHECK_INT(get().count, 42);
    CHECK(apply(CAPSULE_ACT_RESET));
    CHECK_INT(get().count, 0);
    CHECK(!apply(CAPSULE_ACT_START));
    CHECK(!apply(CAPSULE_ACT_PAUSE));
    CHECK(!apply(CAPSULE_ACT_TOGGLE));

    // Reps count only while motion is on.
    capsule_count_rep();
    CHECK_INT(get().count, 0);
    CHECK(apply(CAPSULE_ACT_MOTION_ON));
    CHECK(get().motion);
    capsule_count_rep();
    capsule_count_rep();
    CHECK_INT(get().count, 2);
    CHECK(apply(CAPSULE_ACT_MOTION_OFF));
    capsule_count_rep();
    CHECK_INT(get().count, 2);

    // The count stops at the maximum.
    capsule_set_counter("top", CAPSULE_MAX_COUNT - 1, true);
    CHECK(get().motion);
    CHECK(apply(CAPSULE_ACT_INCREMENT));
    CHECK(apply(CAPSULE_ACT_INCREMENT));
    capsule_count_rep();
    CHECK_INT(get().count, CAPSULE_MAX_COUNT);
}

static void test_new_capsule_replaces_everything(void)
{
    finish_timer(10);
    capsule_set_counter("c", 3, false);
    capsule_state_t state = get();
    CHECK_INT(state.type, CAPSULE_COUNTER);
    CHECK_INT(state.seconds + state.remaining_seconds, 0);
    CHECK(!state.done && !state.running);

    capsule_set_counter("c", 3, true);
    stub_set_ms(T0);
    capsule_set_timer("t", 10, true);
    state = get();
    check_timer(state, 10, true, false);
    CHECK_INT(state.count, 0);
    CHECK(!state.motion);
}

static void test_copy_label_vectors(const char *path)
{
    FILE *file = vector_open(path);
    char line[VECTOR_LINE_MAX], input[VECTOR_LINE_MAX], wanted[VECTOR_LINE_MAX];
    int vectors = 0;
    while (vector_next_line(file, line)) {
        char *first = strchr(line, '|');
        char *second = first ? strchr(first + 1, '|') : NULL;
        if (!second) {
            fprintf(stderr, "bad vector: %s\n", line);
            exit(2);
        }
        *second = '\0';
        vector_bytes(first + 1, input, sizeof(input));
        size_t wanted_len = vector_bytes(second + 1, wanted, sizeof(wanted));

        // Guard bytes after the 48 that a label may use.
        char stored[CAPSULE_LABEL_MAX_BYTES + 8];
        memset(stored, 0x7E, sizeof(stored));
        copy_label(stored, input);
        bool terminated = memchr(stored, '\0', CAPSULE_LABEL_MAX_BYTES) != NULL;
        bool guard_intact = true;
        for (size_t i = CAPSULE_LABEL_MAX_BYTES; i < sizeof(stored); i++) {
            guard_intact = guard_intact && stored[i] == 0x7E;
        }
        check_count++;
        if (!terminated || !guard_intact || strlen(stored) != wanted_len || memcmp(stored, wanted, wanted_len) != 0) {
            check_failures++;
            printf("  FAIL  copy_label stored %zu bytes, wanted %zu (terminated %d, guard intact %d), for:%s\n",
                   terminated ? strlen(stored) : (size_t)0, wanted_len, terminated, guard_intact, first + 1);
        }
        vectors++;
    }
    fclose(file);
    CHECK(vectors >= 40);  // the file was really read
}

static void test_label_reaches_the_state(void)
{
    char long_label[101];
    memset(long_label, 'x', 100);
    long_label[100] = '\0';
    capsule_set_counter(long_label, 0, false);
    CHECK_INT(strlen(get().label), 47);
    stub_set_ms(T0);
    capsule_set_timer(long_label, 5, false);
    CHECK_INT(strlen(get().label), 47);
    capsule_set_timer("", 5, false);
    CHECK_STR(get().label, "");
}

int main(int argc, char **argv)
{
    if (argc != 2) {
        fprintf(stderr, "usage: %s labels.txt\n", argv[0]);
        return 2;
    }
    capsule_init();
    test_idle();
    test_new_timer();
    test_remaining_rounds_up();
    test_done_is_set_exactly_at_the_deadline_and_stays();
    test_pause_at_the_deadline();
    test_pause_and_resume();
    test_actions_after_done();
    test_reset_while_running();
    test_longest_timer();
    test_clock_is_read_once_per_operation();
    test_timer_rejects_counter_actions();
    test_counter();
    test_new_capsule_replaces_everything();
    test_copy_label_vectors(argv[1]);
    test_label_reaches_the_state();
    return check_report("test_capsule");
}

#ifndef HANLIN_QUICKJS_H
#define HANLIN_QUICKJS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct HanlinQuickJSSession HanlinQuickJSSession;

typedef enum HanlinQuickJSStatus {
    HANLIN_QUICKJS_OK = 0,
    HANLIN_QUICKJS_EXCEPTION = 1,
    HANLIN_QUICKJS_TIMED_OUT = 2,
    HANLIN_QUICKJS_CANCELLED = 3,
    HANLIN_QUICKJS_MEMORY_LIMIT = 4,
    HANLIN_QUICKJS_STACK_LIMIT = 5,
    HANLIN_QUICKJS_PENDING_PROMISE = 6,
    HANLIN_QUICKJS_DISPOSED = 7
} HanlinQuickJSStatus;

typedef struct HanlinQuickJSResult {
    HanlinQuickJSStatus status;
    char *value;
    char *message;
} HanlinQuickJSResult;

const char *hanlin_quickjs_engine_version(void);

HanlinQuickJSSession *hanlin_quickjs_session_create(
    size_t memory_limit_bytes,
    size_t stack_limit_bytes
);

void hanlin_quickjs_session_cancel(HanlinQuickJSSession *session);
void hanlin_quickjs_session_reset_cancellation(HanlinQuickJSSession *session);

HanlinQuickJSResult hanlin_quickjs_session_evaluate(
    HanlinQuickJSSession *session,
    const char *source,
    size_t source_length,
    const char *package_local_filename,
    uint64_t timeout_milliseconds
);

HanlinQuickJSResult hanlin_quickjs_session_invoke(
    HanlinQuickJSSession *session,
    const char *canonical_input,
    size_t canonical_input_length,
    uint64_t timeout_milliseconds
);

void hanlin_quickjs_result_destroy(HanlinQuickJSResult result);
void hanlin_quickjs_session_destroy(HanlinQuickJSSession *session);

#ifdef __cplusplus
}
#endif

#endif

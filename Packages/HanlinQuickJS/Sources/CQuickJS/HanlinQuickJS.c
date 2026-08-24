#include "HanlinQuickJS.h"
#include "quickjs.h"

#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

struct HanlinQuickJSSession {
    JSRuntime *runtime;
    JSContext *context;
    atomic_bool cancelled;
    atomic_bool disposed;
    atomic_int interrupt_reason;
    atomic_uint_fast64_t deadline_nanoseconds;
};

enum {
    HANLIN_INTERRUPT_NONE = 0,
    HANLIN_INTERRUPT_CANCELLED = 1,
    HANLIN_INTERRUPT_TIMED_OUT = 2
};

static uint64_t hanlin_monotonic_nanoseconds(void) {
    struct timespec value;
    if (clock_gettime(CLOCK_MONOTONIC, &value) != 0) {
        return 0;
    }
    return ((uint64_t)value.tv_sec * UINT64_C(1000000000))
        + (uint64_t)value.tv_nsec;
}

static int hanlin_interrupt_handler(JSRuntime *runtime, void *opaque) {
    (void)runtime;
    HanlinQuickJSSession *session = opaque;
    if (atomic_load_explicit(&session->cancelled, memory_order_acquire)) {
        atomic_store_explicit(
            &session->interrupt_reason,
            HANLIN_INTERRUPT_CANCELLED,
            memory_order_release
        );
        return 1;
    }
    uint64_t deadline = atomic_load_explicit(
        &session->deadline_nanoseconds,
        memory_order_acquire
    );
    if (deadline != 0 && hanlin_monotonic_nanoseconds() >= deadline) {
        atomic_store_explicit(
            &session->interrupt_reason,
            HANLIN_INTERRUPT_TIMED_OUT,
            memory_order_release
        );
        return 1;
    }
    return 0;
}

static char *hanlin_copy_bytes(const char *source, size_t length) {
    char *copy = malloc(length + 1);
    if (copy == NULL) {
        return NULL;
    }
    if (length > 0) {
        memcpy(copy, source, length);
    }
    copy[length] = '\0';
    return copy;
}

static HanlinQuickJSResult hanlin_result(
    HanlinQuickJSStatus status,
    char *value,
    char *message
) {
    HanlinQuickJSResult result = { status, value, message };
    return result;
}

static HanlinQuickJSResult hanlin_message_result(
    HanlinQuickJSStatus status,
    const char *message
) {
    return hanlin_result(status, NULL, hanlin_copy_bytes(message, strlen(message)));
}

static HanlinQuickJSStatus hanlin_interruption_status(
    HanlinQuickJSSession *session
) {
    switch (atomic_load_explicit(
        &session->interrupt_reason,
        memory_order_acquire
    )) {
    case HANLIN_INTERRUPT_CANCELLED:
        return HANLIN_QUICKJS_CANCELLED;
    case HANLIN_INTERRUPT_TIMED_OUT:
        return HANLIN_QUICKJS_TIMED_OUT;
    default:
        return HANLIN_QUICKJS_EXCEPTION;
    }
}

/*
 * QuickJS-ng's own out-of-memory recovery path can be re-entered while
 * constructing the "out of memory" error itself (further allocations for
 * the Error object can also fail), in which case no real exception value
 * is ever thrown and JS_GetException/JS_ToCStringLen only observe a stale
 * "null". Message-text matching cannot distinguish that from a script
 * that legitimately does `throw null`, so fall back to asking the engine
 * directly whether it is sitting at its configured memory ceiling.
 */
static bool hanlin_memory_exhausted(JSRuntime *runtime) {
    JSMemoryUsage usage;
    JS_ComputeMemoryUsage(runtime, &usage);
    if (usage.malloc_limit <= 0) {
        return false;
    }
    int64_t reserve = usage.malloc_limit / 20;
    /* JS_SetMemoryLimit is enforced against the allocator's malloc_size,
       not the semantic heap estimate in memory_used_size. */
    return usage.malloc_size >= usage.malloc_limit - reserve;
}

static HanlinQuickJSStatus hanlin_failure_status(
    HanlinQuickJSSession *session,
    JSValueConst exception,
    const char *message
) {
    HanlinQuickJSStatus status = hanlin_interruption_status(session);
    if (status != HANLIN_QUICKJS_EXCEPTION) {
        return status;
    }
    if ((JS_IsNull(exception) && hanlin_memory_exhausted(session->runtime))
        || (message != NULL && strstr(message, "out of memory") != NULL)) {
        return HANLIN_QUICKJS_MEMORY_LIMIT;
    }
    if (message != NULL
        && (strstr(message, "Maximum call stack size exceeded") != NULL
            || strstr(message, "stack overflow") != NULL)) {
        return HANLIN_QUICKJS_STACK_LIMIT;
    }
    if (hanlin_memory_exhausted(session->runtime)) {
        return HANLIN_QUICKJS_MEMORY_LIMIT;
    }
    return HANLIN_QUICKJS_EXCEPTION;
}

static HanlinQuickJSResult hanlin_exception_result(
    HanlinQuickJSSession *session,
    JSContext *context
) {
    JSValue exception = JS_GetException(context);
    size_t length = 0;
    const char *text = JS_ToCStringLen(context, &length, exception);
    char *message = text == NULL
        ? hanlin_copy_bytes("Script exception", strlen("Script exception"))
        : hanlin_copy_bytes(text, length);
    HanlinQuickJSStatus status = hanlin_failure_status(
        session,
        exception,
        text == NULL ? NULL : message
    );
    if (text != NULL) {
        JS_FreeCString(context, text);
    }
    JS_FreeValue(context, exception);
    return hanlin_result(status, NULL, message);
}

static bool hanlin_begin_operation(
    HanlinQuickJSSession *session,
    uint64_t timeout_milliseconds
) {
    if (session == NULL || atomic_load_explicit(
        &session->disposed,
        memory_order_acquire
    )) {
        return false;
    }
    atomic_store_explicit(
        &session->interrupt_reason,
        HANLIN_INTERRUPT_NONE,
        memory_order_release
    );
    uint64_t now = hanlin_monotonic_nanoseconds();
    uint64_t timeout_nanoseconds = timeout_milliseconds > UINT64_MAX / UINT64_C(1000000)
        ? UINT64_MAX
        : timeout_milliseconds * UINT64_C(1000000);
    uint64_t deadline = now > UINT64_MAX - timeout_nanoseconds
        ? UINT64_MAX
        : now + timeout_nanoseconds;
    atomic_store_explicit(
        &session->deadline_nanoseconds,
        deadline,
        memory_order_release
    );
    return true;
}

static void hanlin_end_operation(HanlinQuickJSSession *session) {
    atomic_store_explicit(
        &session->deadline_nanoseconds,
        0,
        memory_order_release
    );
}

const char *hanlin_quickjs_engine_version(void) {
    return JS_GetVersion();
}

HanlinQuickJSSession *hanlin_quickjs_session_create(
    size_t memory_limit_bytes,
    size_t stack_limit_bytes
) {
    HanlinQuickJSSession *session = calloc(1, sizeof(*session));
    if (session == NULL) {
        return NULL;
    }
    atomic_init(&session->cancelled, false);
    atomic_init(&session->disposed, false);
    atomic_init(&session->interrupt_reason, HANLIN_INTERRUPT_NONE);
    atomic_init(&session->deadline_nanoseconds, 0);
    session->runtime = JS_NewRuntime();
    if (session->runtime == NULL) {
        free(session);
        return NULL;
    }
    JS_SetMemoryLimit(session->runtime, memory_limit_bytes);
    JS_SetMaxStackSize(session->runtime, stack_limit_bytes);
    JS_SetCanBlock(session->runtime, false);
    JS_SetInterruptHandler(
        session->runtime,
        hanlin_interrupt_handler,
        session
    );
    session->context = JS_NewContext(session->runtime);
    if (session->context == NULL) {
        JS_FreeRuntime(session->runtime);
        free(session);
        return NULL;
    }
    return session;
}

void hanlin_quickjs_session_cancel(HanlinQuickJSSession *session) {
    if (session != NULL) {
        atomic_store_explicit(&session->cancelled, true, memory_order_release);
    }
}

void hanlin_quickjs_session_reset_cancellation(HanlinQuickJSSession *session) {
    if (session != NULL) {
        atomic_store_explicit(&session->cancelled, false, memory_order_release);
    }
}

HanlinQuickJSResult hanlin_quickjs_session_evaluate(
    HanlinQuickJSSession *session,
    const char *source,
    size_t source_length,
    const char *package_local_filename,
    uint64_t timeout_milliseconds
) {
    hanlin_quickjs_session_reset_cancellation(session);
    if (!hanlin_begin_operation(session, timeout_milliseconds)) {
        return hanlin_message_result(HANLIN_QUICKJS_DISPOSED, "Script session is disposed");
    }
    JSValue value = JS_Eval(
        session->context,
        source,
        source_length,
        package_local_filename,
        JS_EVAL_TYPE_GLOBAL | JS_EVAL_FLAG_STRICT
    );
    HanlinQuickJSResult result = JS_IsException(value)
        ? hanlin_exception_result(session, session->context)
        : hanlin_result(HANLIN_QUICKJS_OK, NULL, NULL);
    JS_FreeValue(session->context, value);
    hanlin_end_operation(session);
    return result;
}

HanlinQuickJSResult hanlin_quickjs_session_invoke(
    HanlinQuickJSSession *session,
    const char *canonical_input,
    size_t canonical_input_length,
    uint64_t timeout_milliseconds
) {
    if (!hanlin_begin_operation(session, timeout_milliseconds)) {
        return hanlin_message_result(HANLIN_QUICKJS_DISPOSED, "Script session is disposed");
    }
    JSContext *context = session->context;
    JSValue global = JS_GetGlobalObject(context);
    JSValue function = JS_GetPropertyStr(context, global, "__hanlinInvoke");
    JSValue argument = JS_NewStringLen(
        context,
        canonical_input,
        canonical_input_length
    );
    JSValue promise = JS_Call(context, function, global, 1, &argument);
    JS_FreeValue(context, argument);
    JS_FreeValue(context, function);
    JS_FreeValue(context, global);
    if (JS_IsException(promise)) {
        HanlinQuickJSResult result = hanlin_exception_result(session, context);
        JS_FreeValue(context, promise);
        hanlin_end_operation(session);
        return result;
    }

    JSPromiseStateEnum state = JS_PromiseState(context, promise);
    while (state == JS_PROMISE_PENDING) {
        JSContext *job_context = NULL;
        int executed = JS_ExecutePendingJob(session->runtime, &job_context);
        if (executed < 0) {
            HanlinQuickJSResult result = hanlin_exception_result(
                session,
                job_context == NULL ? context : job_context
            );
            JS_FreeValue(context, promise);
            hanlin_end_operation(session);
            return result;
        }
        if (executed == 0) {
            JS_FreeValue(context, promise);
            hanlin_end_operation(session);
            return hanlin_message_result(
                HANLIN_QUICKJS_PENDING_PROMISE,
                "Script promise cannot make progress without an unavailable host capability"
            );
        }
        state = JS_PromiseState(context, promise);
    }

    JSValue settled = JS_PromiseResult(context, promise);
    JS_FreeValue(context, promise);
    if (state == JS_PROMISE_REJECTED) {
        size_t length = 0;
        const char *text = JS_ToCStringLen(context, &length, settled);
        char *message = text == NULL
            ? hanlin_copy_bytes("Script promise rejected", strlen("Script promise rejected"))
            : hanlin_copy_bytes(text, length);
        HanlinQuickJSStatus status = hanlin_failure_status(
            session,
            settled,
            text == NULL ? NULL : message
        );
        if (text != NULL) {
            JS_FreeCString(context, text);
        }
        JS_FreeValue(context, settled);
        hanlin_end_operation(session);
        return hanlin_result(status, NULL, message);
    }

    size_t length = 0;
    const char *text = JS_ToCStringLen(context, &length, settled);
    if (text == NULL) {
        JS_FreeValue(context, settled);
        HanlinQuickJSResult result = hanlin_exception_result(session, context);
        hanlin_end_operation(session);
        return result;
    }
    char *value = hanlin_copy_bytes(text, length);
    JS_FreeCString(context, text);
    JS_FreeValue(context, settled);
    hanlin_end_operation(session);
    if (value == NULL) {
        return hanlin_message_result(
            HANLIN_QUICKJS_MEMORY_LIMIT,
            "Unable to allocate Script result"
        );
    }
    return hanlin_result(HANLIN_QUICKJS_OK, value, NULL);
}

void hanlin_quickjs_result_destroy(HanlinQuickJSResult result) {
    free(result.value);
    free(result.message);
}

void hanlin_quickjs_session_destroy(HanlinQuickJSSession *session) {
    if (session == NULL) {
        return;
    }
    bool already_disposed = atomic_exchange_explicit(
        &session->disposed,
        true,
        memory_order_acq_rel
    );
    if (!already_disposed) {
        JS_FreeContext(session->context);
        JS_FreeRuntime(session->runtime);
    }
    free(session);
}

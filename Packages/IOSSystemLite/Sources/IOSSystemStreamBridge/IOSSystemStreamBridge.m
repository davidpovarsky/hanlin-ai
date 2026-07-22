#include "IOSSystemStreamBridge.h"

#include <ios_system/ios_system.h>

void hanlin_ios_system_set_streams(
    FILE *standard_input,
    FILE *standard_output,
    FILE *standard_error
) {
    ios_setStreams(standard_input, standard_output, standard_error);
    thread_stdin = standard_input;
    thread_stdout = standard_output;
    thread_stderr = standard_error;
}

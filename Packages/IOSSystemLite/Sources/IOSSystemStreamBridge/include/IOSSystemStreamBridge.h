#ifndef IOSSystemStreamBridge_h
#define IOSSystemStreamBridge_h

#include <stdio.h>

void hanlin_ios_system_set_streams(
    FILE *standard_input,
    FILE *standard_output,
    FILE *standard_error
);

#endif

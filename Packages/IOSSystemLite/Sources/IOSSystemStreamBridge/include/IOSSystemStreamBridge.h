#ifndef IOSSystemStreamBridge_h
#define IOSSystemStreamBridge_h

#include <stdio.h>

#if defined(__OBJC__)
#import <Foundation/Foundation.h>
#else
#include <CoreFoundation/CoreFoundation.h>
typedef struct objc_object NSURL;
typedef struct objc_object NSArray;
#endif

#if defined(__cplusplus)
extern "C" {
#endif

void hanlin_ios_system_set_streams(
    FILE *standard_input,
    FILE *standard_output,
    FILE *standard_error
);

int ios_executable(const char *inputCmd);
int ios_system(const char *inputCmd);
NSArray *commandsAsArray(void);
void initializeEnvironment(void);
int ios_setMiniRootURL(NSURL *url);
void ios_setDirectoryURL(NSURL *workingDirectoryURL);

#if defined(__cplusplus)
}
#endif

#endif

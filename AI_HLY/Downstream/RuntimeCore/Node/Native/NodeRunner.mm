#include "NodeRunner.h"
#include <Foundation/Foundation.h>
#include <NodeMobile/NodeMobile.h>
#include <atomic>
#include <cstdlib>
#include <cstring>

@interface HanlinNodeEngine : NSObject
+ (void)runArguments:(NSArray<NSString *> *)arguments;
@end

@implementation HanlinNodeEngine

+ (void)runArguments:(NSArray<NSString *> *)arguments {
    @autoreleasepool {
        // Node/libuv rewrites argv in place and requires every argument string
        // to live in one contiguous allocation for the entire node_start call.
        size_t storageSize = 0;
        for (NSString *argument in arguments) {
            const char *value = argument.UTF8String;
            storageSize += (value == nullptr ? 0 : std::strlen(value)) + 1;
        }

        // Match NodeMobile's native iOS runner: node_start/uv_setup_args is a
        // process-lifetime one-shot API, so keep C-owned argv storage alive for
        // that lifetime instead of placing it in destructible C++ containers.
        char *storage = static_cast<char *>(std::calloc(storageSize, sizeof(char)));
        char **argv = static_cast<char **>(
            std::calloc(arguments.count + 1, sizeof(char *))
        );
        if (storage == nullptr || argv == nullptr) {
            std::free(storage);
            std::free(argv);
            return;
        }

        char *position = storage;
        NSUInteger index = 0;
        for (NSString *argument in arguments) {
            const char *value = argument.UTF8String;
            const size_t length = value == nullptr ? 0 : std::strlen(value);
            argv[index] = position;
            if (length > 0) {
                std::memcpy(position, value, length);
            }
            position += length + 1;
            index += 1;
        }
        node_start(static_cast<int>(arguments.count), argv);
    }
}

@end

int HanlinNodeStart(const char *argumentsJSON) {
    static std::atomic_bool started(false);
    bool expected = false;
    if (!started.compare_exchange_strong(expected, true)) {
        return 1;
    }
    if (argumentsJSON == nullptr) {
        started.store(false);
        return -1;
    }

    NSData *data = [NSData dataWithBytes:argumentsJSON length:strlen(argumentsJSON)];
    NSError *error = nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (error != nil || ![object isKindOfClass:[NSArray class]]) {
        started.store(false);
        return -2;
    }
    NSArray<NSString *> *arguments = (NSArray<NSString *> *)object;
    for (id argument in arguments) {
        if (![argument isKindOfClass:[NSString class]]) {
            started.store(false);
            return -3;
        }
    }

    NSThread *thread = [[NSThread alloc] initWithBlock:^{
        [HanlinNodeEngine runArguments:arguments];
    }];
    thread.name = @"Hanlin Embedded Node";
    thread.stackSize = 2 * 1024 * 1024;
    [thread start];
    return 0;
}

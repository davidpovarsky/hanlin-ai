#include "NodeRunner.h"
#include <Foundation/Foundation.h>
#include <NodeMobile/NodeMobile.h>
#include <atomic>
#include <cstring>
#include <vector>

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

        std::vector<char> storage(storageSize, '\0');
        std::vector<char *> argv;
        argv.reserve(arguments.count);
        char *position = storage.data();
        for (NSString *argument in arguments) {
            const char *value = argument.UTF8String;
            const size_t length = value == nullptr ? 0 : std::strlen(value);
            argv.push_back(position);
            if (length > 0) {
                std::memcpy(position, value, length);
            }
            position += length + 1;
        }
        node_start(static_cast<int>(argv.size()), argv.data());
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

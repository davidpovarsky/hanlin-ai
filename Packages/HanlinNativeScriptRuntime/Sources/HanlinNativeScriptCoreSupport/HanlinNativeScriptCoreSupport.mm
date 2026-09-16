#import "HanlinNativeScriptCoreSupport.h"
#import "NativeScriptEmbedder.h"
#import <NativeScript/NativeScript.h>
#import <exception>
#import <string>

namespace tns {
class __attribute__((visibility("default"))) NativeScriptException {
public:
    ~NativeScriptException();
    const std::string& getMessage() const { return message_; }
    const std::string& getStackTrace() const { return stackTrace_; }
private:
    void* javascriptException_;
    std::string name_;
    std::string message_;
    std::string stackTrace_;
    std::string fullMessage_;
};
}



static NSString *HanlinFormatNativeScriptException(const tns::NativeScriptException &e) {
    NSString *message = [NSString stringWithUTF8String:e.getMessage().c_str()] ?: @"";
    NSString *stack = [NSString stringWithUTF8String:e.getStackTrace().c_str()] ?: @"";
    if (stack.length > 0) {
        return [NSString stringWithFormat:@"%@\nStack:\n%@", message, stack];
    }
    return message;
}

NSErrorDomain const HanlinNativeScriptRuntimeErrorDomain = @"com.hanlin.nativescript-runtime";

static NSError *HanlinNativeScriptError(HanlinNativeScriptRuntimeErrorCode code, NSString *message) {
    return [NSError errorWithDomain:HanlinNativeScriptRuntimeErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

@interface HanlinNativeScriptRuntimeHost ()
@property(nonatomic, strong, nullable) NativeScript *runtime;
@end

@implementation HanlinNativeScriptRuntimeHost

- (nullable instancetype)initWithBaseDirectory:(NSString *)baseDirectory
                                applicationPath:(NSString *)applicationPath
                                          error:(NSError **)error {
    if (baseDirectory.length == 0 || applicationPath.length == 0) {
        if (error) {
            *error = HanlinNativeScriptError(
                HanlinNativeScriptRuntimeErrorInvalidConfiguration,
                @"NativeScript requires non-empty base and application paths."
            );
        }
        return nil;
    }

    self = [super init];
    if (!self) { return nil; }

    try {
        @try {
            Config *config = [[Config alloc] init];
            config.BaseDir = baseDirectory;
            config.ApplicationPath = applicationPath;
            config.IsDebug = NO;
            config.LogToSystemConsole = YES;
            self.runtime = [[NativeScript alloc] initWithConfig:config];
        } @catch (NSException *exception) {
            NSString *detail = [NSString stringWithFormat:@"NativeScript runtime initialization NSException: %@ (reason: %@)",
                                exception.name ?: @"Unknown",
                                exception.reason ?: @"No reason provided"];
            NSLog(@"[HanlinNativeScript] %@", detail);
            if (error) {
                *error = HanlinNativeScriptError(
                    HanlinNativeScriptRuntimeErrorInitializationFailed,
                    detail
                );
            }
            return nil;
        }
    } catch (const tns::NativeScriptException &e) {
        NSString *detail = [NSString stringWithFormat:@"NativeScript runtime initialization failed: %@", HanlinFormatNativeScriptException(e)];
        NSLog(@"[HanlinNativeScript] %@", detail);
        if (error) {
            *error = HanlinNativeScriptError(
                HanlinNativeScriptRuntimeErrorInitializationFailed,
                detail
            );
        }
        return nil;
    } catch (const std::exception &e) {
        NSString *detail = [NSString stringWithFormat:@"NativeScript runtime initialization C++ exception: %s", e.what()];
        NSLog(@"[HanlinNativeScript] %@", detail);
        if (error) {
            *error = HanlinNativeScriptError(
                HanlinNativeScriptRuntimeErrorInitializationFailed,
                detail
            );
        }
        return nil;
    } catch (...) {
        NSString *detail = nil;
        std::exception_ptr p = std::current_exception();
        try {
            if (p) std::rethrow_exception(p);
        } catch (const tns::NativeScriptException &e) {
            detail = [NSString stringWithFormat:@"NativeScript runtime initialization failed: %@", HanlinFormatNativeScriptException(e)];
        } catch (const std::exception &e) {
            detail = [NSString stringWithFormat:@"NativeScript initialization C++ exception: %s", e.what()];
        } catch (id objcEx) {
            detail = [NSString stringWithFormat:@"NativeScript initialization ObjC exception: %@", objcEx];
        } catch (...) {
            detail = @"NativeScript runtime initialization raised an unknown native exception.";
        }
        NSLog(@"[HanlinNativeScript] %@", detail);
        if (error) {
            *error = HanlinNativeScriptError(
                HanlinNativeScriptRuntimeErrorInitializationFailed,
                detail
            );
        }
        return nil;
    }
    return self;
}

- (BOOL)runMainApplicationWithError:(NSError **)error {
    if (!self.runtime) {
        if (error) {
            *error = HanlinNativeScriptError(
                HanlinNativeScriptRuntimeErrorExecutionFailed,
                @"NativeScript runtime is not active."
            );
        }
        return NO;
    }
    try {
        @try {
            NSLog(@"HANLIN_NS_BEFORE_RUN_MAIN");
            [self.runtime runMainApplication];
            NSLog(@"HANLIN_NS_AFTER_RUN_MAIN");
        } @catch (NSException *exception) {
            NSString *detail = [NSString stringWithFormat:@"NativeScript script execution NSException: %@ (reason: %@)",
                                exception.name ?: @"Unknown",
                                exception.reason ?: @"No reason provided"];
            NSLog(@"[HanlinNativeScript] %@", detail);
            if (error) {
                *error = HanlinNativeScriptError(
                    HanlinNativeScriptRuntimeErrorExecutionFailed,
                    detail
                );
            }
            return NO;
        } @catch (id unknownObjc) {
            NSString *detail = [NSString stringWithFormat:@"NativeScript script execution ObjC exception: %@", unknownObjc];
            NSLog(@"[HanlinNativeScript] %@", detail);
            if (error) {
                *error = HanlinNativeScriptError(
                    HanlinNativeScriptRuntimeErrorExecutionFailed,
                    detail
                );
            }
            return NO;
        }
    } catch (const tns::NativeScriptException &e) {
        NSString *detail = [NSString stringWithFormat:@"NativeScript script execution failed: %@", HanlinFormatNativeScriptException(e)];
        NSLog(@"[HanlinNativeScript] %@", detail);
        if (error) {
            *error = HanlinNativeScriptError(
                HanlinNativeScriptRuntimeErrorExecutionFailed,
                detail
            );
        }
        return NO;
    } catch (const std::exception &e) {
        NSString *detail = [NSString stringWithFormat:@"NativeScript script execution C++ exception: %s", e.what()];
        NSLog(@"[HanlinNativeScript] %@", detail);
        if (error) {
            *error = HanlinNativeScriptError(
                HanlinNativeScriptRuntimeErrorExecutionFailed,
                detail
            );
        }
        return NO;
    } catch (...) {
        NSString *detail = nil;
        std::exception_ptr p = std::current_exception();
        try {
            if (p) std::rethrow_exception(p);
        } catch (const tns::NativeScriptException &e) {
            detail = [NSString stringWithFormat:@"NativeScript script execution failed: %@", HanlinFormatNativeScriptException(e)];
        } catch (const std::exception &e) {
            detail = [NSString stringWithFormat:@"NativeScript C++ exception: %s", e.what()];
        } catch (id objcEx) {
            detail = [NSString stringWithFormat:@"NativeScript ObjC exception: %@", objcEx];
        } catch (...) {
            detail = @"NativeScript script execution raised an unknown native exception.";
        }
        NSLog(@"[HanlinNativeScript] %@", detail);
        if (error) {
            *error = HanlinNativeScriptError(
                HanlinNativeScriptRuntimeErrorExecutionFailed,
                detail
            );
        }
        return NO;
    }
    return YES;
}

- (void)shutdown {
    if (self.runtime) {
        try {
            @try {
                [self.runtime shutdownRuntime];
            } @catch (NSException *exception) {
                NSLog(@"[HanlinNativeScript] Exception during shutdownRuntime: %@", exception);
            }
        } catch (const tns::NativeScriptException &e) {
            NSLog(@"[HanlinNativeScript] NativeScript exception during shutdownRuntime: %@", HanlinFormatNativeScriptException(e));
        } catch (const std::exception &e) {
            NSLog(@"[HanlinNativeScript] C++ exception during shutdownRuntime: %s", e.what());
        } catch (...) {
            NSLog(@"[HanlinNativeScript] Unknown exception during shutdownRuntime");
        }
        self.runtime = nil;
    }
}

- (void)dealloc {
    [self shutdown];
}

@end

@implementation HanlinNativeScriptContainerController
@end

@interface HanlinNativeScriptPresenter () <NativeScriptEmbedderDelegate>
@property(nonatomic, strong) HanlinNativeScriptContainerController *containerController;
@property(nonatomic, strong, nullable) UIViewController *guestController;
@end

@implementation HanlinNativeScriptPresenter

- (instancetype)init {
    self = [super init];
    if (self) {
        _containerController = [[HanlinNativeScriptContainerController alloc] init];
    }
    return self;
}

- (void)install {
    [[NativeScriptEmbedder sharedInstance] setDelegate:self];
}

- (id)presentNativeScriptApp:(UIViewController *)viewController {
    [self detachGuestController];
    self.guestController = viewController;
    [self.containerController addChildViewController:viewController];
    viewController.view.frame = self.containerController.view.bounds;
    viewController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.containerController.view addSubview:viewController.view];
    [viewController didMoveToParentViewController:self.containerController];
    return self.containerController;
}

- (void)detach {
    if ([NativeScriptEmbedder sharedInstance].delegate == self) {
        [[NativeScriptEmbedder sharedInstance] setDelegate:nil];
    }
    [self detachGuestController];
}

- (void)detachGuestController {
    UIViewController *guest = self.guestController;
    if (!guest) { return; }
    [guest willMoveToParentViewController:nil];
    [guest.view removeFromSuperview];
    [guest removeFromParentViewController];
    self.guestController = nil;
}

@end

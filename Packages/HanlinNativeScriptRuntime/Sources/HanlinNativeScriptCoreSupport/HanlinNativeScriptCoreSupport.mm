#import "HanlinNativeScriptCoreSupport.h"
#import "NativeScriptEmbedder.h"
#import "fishhook.h"
#import <NativeScript/NativeScript.h>
#import <dlfcn.h>
#import <fcntl.h>
#import <unistd.h>
#import <atomic>
#import <exception>
#import <fstream>
#import <string>
#import <sstream>

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

typedef bool (*TNSIsESModuleFn)(const std::string&);
static TNSIsESModuleFn s_tnsIsESModule = nullptr;

static void InitTNSSymbols() {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s_tnsIsESModule = (TNSIsESModuleFn)dlsym(RTLD_DEFAULT, "_ZN3tns10IsESModuleERKNSt3__112basic_stringIcNS0_11char_traitsIcEENS0_9allocatorIcEEEE");
        if (!s_tnsIsESModule) {
            s_tnsIsESModule = (TNSIsESModuleFn)dlsym(RTLD_DEFAULT, "__ZN3tns10IsESModuleERKNSt3__112basic_stringIcNS0_11char_traitsIcEENS0_9allocatorIcEEEE");
        }
        if (s_tnsIsESModule) {
            NSLog(@"[HanlinLoaderTrace] Successfully resolved tns::IsESModule");
        } else {
            NSLog(@"[HanlinLoaderTrace] Warning: could not resolve tns::IsESModule via dlsym");
        }
    });
}

static BOOL HanlinStringEndsWith(const char *str, const char *suffix) {
    if (!str || !suffix) return NO;
    size_t strLen = strlen(str);
    size_t sufLen = strlen(suffix);
    if (strLen < sufLen) return NO;
    return strcmp(str + (strLen - sufLen), suffix) == 0;
}

static std::atomic<uint32_t> s_loaderTraceSeq{0};

static BOOL HanlinIsWatchedPath(const char *path) {
    if (!path) return NO;
    if (strstr(path, "nativescript") == NULL &&
        strstr(path, "NativeScript") == NULL &&
        strstr(path, "ScriptingPlatform") == NULL) {
        return NO;
    }
    return (HanlinStringEndsWith(path, ".js") ||
            HanlinStringEndsWith(path, ".mjs") ||
            HanlinStringEndsWith(path, ".cjs") ||
            strstr(path, "package.json") != NULL);
}

static thread_local bool s_in_hook = false;

static void hanlin_log_file_access(int fd, const char *path, const char *op) {
    if (!HanlinIsWatchedPath(path)) {
        return;
    }

    uint32_t seq = ++s_loaderTraceSeq;

    char canonical[PATH_MAX] = {0};
    if (realpath(path, canonical) == nullptr) {
        strncpy(canonical, path, sizeof(canonical) - 1);
    }

    InitTNSSymbols();
    const char *isESMStr = "unknown";
    if (s_tnsIsESModule) {
        try {
            std::string p(path);
            isESMStr = s_tnsIsESModule(p) ? "YES" : "NO";
        } catch (...) {
            isESMStr = "threw";
        }
    }

    char firstLineBuf[128] = {0};
    if (fd >= 0) {
        ssize_t bytesRead = pread(fd, firstLineBuf, sizeof(firstLineBuf) - 1, 0);
        if (bytesRead > 0) {
            firstLineBuf[bytesRead] = '\0';
            for (ssize_t i = 0; i < bytesRead; ++i) {
                if (firstLineBuf[i] == '\r' || firstLineBuf[i] == '\n') {
                    firstLineBuf[i] = '\0';
                    break;
                }
            }
        } else {
            strncpy(firstLineBuf, "<empty>", sizeof(firstLineBuf) - 1);
        }
    } else {
        strncpy(firstLineBuf, "<no-fd>", sizeof(firstLineBuf) - 1);
    }

    NSLog(@"[HanlinLoaderTrace #%u] %s | req=%s | real=%s | isESM_query=%s | first=\"%s\"",
          seq, op, path, canonical, isESMStr, firstLineBuf);
}

static int (*orig_open)(const char *, int, ...) = nullptr;

static int hanlin_hooked_open(const char *path, int oflag, ...) {
    mode_t mode = 0;
    if (oflag & O_CREAT) {
        va_list ap;
        va_start(ap, oflag);
        mode = va_arg(ap, int);
        va_end(ap);
    }

    int fd = orig_open ? orig_open(path, oflag, mode) : open(path, oflag, mode);

    if (!s_in_hook && fd >= 0 && path != nullptr) {
        s_in_hook = true;
        hanlin_log_file_access(fd, path, "OPEN");
        s_in_hook = false;
    }
    return fd;
}

static FILE *(*orig_fopen)(const char *, const char *) = nullptr;

static FILE *hanlin_hooked_fopen(const char *path, const char *mode) {
    FILE *f = orig_fopen ? orig_fopen(path, mode) : fopen(path, mode);
    if (!s_in_hook && f != nullptr && path != nullptr) {
        s_in_hook = true;
        int fd = fileno(f);
        hanlin_log_file_access(fd, path, "FOPEN");
        s_in_hook = false;
    }
    return f;
}

static void HanlinInstallLoaderHooks() {
    static dispatch_once_t hookToken;
    dispatch_once(&hookToken, ^{
        InitTNSSymbols();
        struct rebinding rebindings[] = {
            {"open", (void *)hanlin_hooked_open, (void **)&orig_open},
            {"fopen", (void *)hanlin_hooked_fopen, (void **)&orig_fopen}
        };
        int rc = rebind_symbols(rebindings, 2);
        NSLog(@"[HanlinLoaderTrace] rebind_symbols installed (rc=%d)", rc);
    });
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

    HanlinInstallLoaderHooks();

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
    HanlinInstallLoaderHooks();
    NSLog(@"[HanlinLoaderTrace] Starting runMainApplication with active loader hooks...");
    try {
        @try {
            NSLog(@"HANLIN_NS_BEFORE_RUN_MAIN");
            [self.runtime runMainApplication];
            NSLog(@"HANLIN_NS_AFTER_RUN_MAIN");
        } @catch (NSException *exception) {
            NSString *detail = [NSString stringWithFormat:@"NativeScript script execution NSException: %@ (reason: %@)",
                                exception.name ?: @"Unknown",
                                exception.reason ?: @"No reason provided"];
            NSLog(@"[HanlinLoaderTrace] !!! NSException: %@", detail);
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
        NSLog(@"[HanlinLoaderTrace] !!! NativeScript script execution failed: %@", detail);
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

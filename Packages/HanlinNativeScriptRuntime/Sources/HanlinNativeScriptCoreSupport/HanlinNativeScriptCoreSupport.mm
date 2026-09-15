#import "HanlinNativeScriptCoreSupport.h"
#import "NativeScriptEmbedder.h"
#import "fishhook.h"
#import <NativeScript/NativeScript.h>
#import <dlfcn.h>
#import <fcntl.h>
#import <unistd.h>
#import <exception>
#import <filesystem>
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
        s_tnsIsESModule = (TNSIsESModuleFn)dlsym(RTLD_DEFAULT, "__ZN3tns10IsESModuleERKNSt3__112basic_stringIcNS0_11char_traitsIcEENS0_9allocatorIcEEEE");
        if (s_tnsIsESModule) {
            NSLog(@"[HanlinLoaderTrace] Successfully resolved tns::IsESModule");
        } else {
            NSLog(@"[HanlinLoaderTrace] Warning: could not resolve tns::IsESModule via dlsym");
        }
    });
}

static std::string HanlinReadFirstLine(const std::string& path) {
    std::ifstream file(path);
    if (!file.is_open()) { return "<cannot open>"; }
    std::string line;
    if (std::getline(file, line)) {
        if (line.size() > 140) {
            line = line.substr(0, 140) + "...";
        }
        return line;
    }
    return "<empty>";
}

static std::string HanlinFindNearestPackageJson(const std::string& startDir) {
    std::filesystem::path current(startDir);
    while (!current.empty() && current != current.root_path()) {
        std::filesystem::path pkg = current / "package.json";
        std::error_code ec;
        if (std::filesystem::exists(pkg, ec) && !ec) {
            return pkg.string();
        }
        current = current.parent_path();
    }
    return "";
}

static std::string HanlinReadPackageJsonType(const std::string& pkgJsonPath) {
    if (pkgJsonPath.empty()) return "<none>";
    std::ifstream file(pkgJsonPath);
    if (!file.is_open()) return "<cannot open>";
    std::string content((std::istreambuf_iterator<char>(file)),
                        std::istreambuf_iterator<char>());
    size_t typePos = content.find("\"type\"");
    if (typePos != std::string::npos) {
        size_t colon = content.find(':', typePos + 6);
        if (colon != std::string::npos) {
            size_t valStart = content.find('"', colon + 1);
            if (valStart != std::string::npos) {
                size_t valEnd = content.find('"', valStart + 1);
                if (valEnd != std::string::npos) {
                    return content.substr(valStart + 1, valEnd - valStart - 1);
                }
            }
        }
    }
    return "<no-type-field>";
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

    if (path != nullptr) {
        std::string p(path);
        if (p.ends_with(".js") || p.ends_with(".mjs") || p.ends_with(".cjs") || p.ends_with("package.json")) {
            char canonical[PATH_MAX] = {0};
            if (realpath(path, canonical) == nullptr) {
                strncpy(canonical, path, sizeof(canonical) - 1);
            }

            InitTNSSymbols();
            bool isESM = false;
            if (s_tnsIsESModule) {
                isESM = s_tnsIsESModule(p);
            }

            std::filesystem::path fp(p);
            std::string nearestPkg = HanlinFindNearestPackageJson(fp.parent_path().string());
            std::string pkgType = HanlinReadPackageJsonType(nearestPkg);
            std::string firstLine = HanlinReadFirstLine(p);

            NSLog(@"[HanlinLoaderTrace] >>> OPEN: %s", path);
            NSLog(@"[HanlinLoaderTrace]     CANONICAL: %s", canonical);
            NSLog(@"[HanlinLoaderTrace]     IS_ESM: %s", (s_tnsIsESModule ? (isESM ? "YES (ESM)" : "NO (CommonJS)") : "UNKNOWN"));
            NSLog(@"[HanlinLoaderTrace]     PKG_JSON: %s", (nearestPkg.empty() ? "<NOT FOUND>" : nearestPkg.c_str()));
            NSLog(@"[HanlinLoaderTrace]     PKG_TYPE: %s", pkgType.c_str());
            NSLog(@"[HanlinLoaderTrace]     FIRST_LINE: %s", firstLine.c_str());
        }
    }
    return fd;
}

static void HanlinInstallLoaderHooks() {
    static dispatch_once_t hookToken;
    dispatch_once(&hookToken, ^{
        InitTNSSymbols();
        struct rebinding rebindings[] = {
            {"open", (void *)hanlin_hooked_open, (void **)&orig_open}
        };
        int rc = rebind_symbols(rebindings, 1);
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
            // Use the runtime's supported package entry loader. Application.run()
            // detects NativeScriptEmbedder's delegate and attaches to the host
            // controller without starting a second UIApplicationMain.
            [self.runtime runMainApplication];
            NSLog(@"[HanlinLoaderTrace] runMainApplication returned successfully.");
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

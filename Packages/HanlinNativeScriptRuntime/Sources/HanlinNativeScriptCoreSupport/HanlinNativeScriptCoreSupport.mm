#import "HanlinNativeScriptCoreSupport.h"
#import "NativeScriptEmbedder.h"
#import <NativeScript/NativeScript.h>

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
            if (error) {
                *error = HanlinNativeScriptError(
                    HanlinNativeScriptRuntimeErrorInitializationFailed,
                    exception.reason ?: @"NativeScript runtime initialization failed."
                );
            }
            return nil;
        }
    } catch (...) {
        if (error) {
            *error = HanlinNativeScriptError(
                HanlinNativeScriptRuntimeErrorInitializationFailed,
                @"NativeScript runtime initialization raised a native exception."
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
            // Use the runtime's supported package entry loader. Application.run()
            // detects NativeScriptEmbedder's delegate and attaches to the host
            // controller without starting a second UIApplicationMain.
            [self.runtime runMainApplication];
        } @catch (NSException *exception) {
            if (error) {
                *error = HanlinNativeScriptError(
                    HanlinNativeScriptRuntimeErrorExecutionFailed,
                    exception.reason ?: @"NativeScript script execution failed."
                );
            }
            return NO;
        }
    } catch (...) {
        if (error) {
            *error = HanlinNativeScriptError(
                HanlinNativeScriptRuntimeErrorExecutionFailed,
                @"NativeScript script execution raised a native exception."
            );
        }
        return NO;
    }
    return YES;
}

- (void)shutdown {
    if (self.runtime) {
        [self.runtime shutdownRuntime];
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

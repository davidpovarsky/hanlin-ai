#import "HanlinNativeScriptCoreSupport.h"
#import "NativeScriptEmbedder.h"
#import <NativeScript/NativeScript.h>
#import <exception>
#import <string>

extern "C" NSString * _Nullable HanlinNativeServicesPrepareSessionBootstrap(NSString *sessionID);

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

- (BOOL)bindHostServicesSessionID:(NSString *)sessionID error:(NSError **)error {
    if (!self.runtime) {
        if (error) {
            *error = HanlinNativeScriptError(
                HanlinNativeScriptRuntimeErrorExecutionFailed,
                @"NativeScript runtime is not active."
            );
        }
        return NO;
    }

    NSString *token = HanlinNativeServicesPrepareSessionBootstrap(sessionID);
    if (token.length == 0) {
        if (error) {
            *error = HanlinNativeScriptError(
                HanlinNativeScriptRuntimeErrorInvalidConfiguration,
                @"No Host Services provider is registered for this NativeScript session."
            );
        }
        return NO;
    }

    NSString *bootstrap = [NSString stringWithFormat:
        @"(() => { const bridgeClass = HanlinNativeServicesBridge; "
         "const bridge = bridgeClass.claimSessionBridgeWithToken('%@'); "
         "if (!bridge) throw new Error('Unable to bind Hanlin Host Services session'); "
         "Object.defineProperty(globalThis, 'HanlinNativeServicesBridge', "
         "{ value: bridge, writable: false, configurable: false }); })();",
        token
    ];

    @try {
        [self.runtime runScriptString:bootstrap runLoop:NO];
    } @catch (NSException *exception) {
        if (error) {
            NSString *detail = [NSString stringWithFormat:@"NativeScript Host Services binding failed: %@",
                                exception.reason ?: exception.name];
            *error = HanlinNativeScriptError(HanlinNativeScriptRuntimeErrorExecutionFailed, detail);
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

static void HanlinLogControllerHierarchy(NSString *context, UIViewController *vc) {
    if (!vc) {
        NSLog(@"[HanlinHostDiag] context=%@ controller=(nil)", context);
        return;
    }
    UIView *view = vc.isViewLoaded ? vc.view : nil;
    BOOL hasWindow = (view && view.window != nil);
    BOOL isInHierarchy = (view && view.window != nil && !view.hidden && view.alpha > 0.01);

    NSMutableString *childrenDesc = [NSMutableString string];
    [childrenDesc appendString:@"["];
    for (NSUInteger i = 0; i < vc.childViewControllers.count; i++) {
        UIViewController *child = vc.childViewControllers[i];
        if (i > 0) [childrenDesc appendString:@", "];
        [childrenDesc appendFormat:@"%@:%p", NSStringFromClass(child.class), child];
    }
    [childrenDesc appendString:@"]"];

    NSString *frameStr = view ? NSStringFromCGRect(view.frame) : @"(no-view)";
    NSString *boundsStr = view ? NSStringFromCGRect(view.bounds) : @"(no-view)";
    BOOL hidden = view ? view.hidden : YES;
    CGFloat alpha = view ? view.alpha : 0.0;

    NSLog(@"[HanlinHostDiag] context=%@ vc=%@:%p parent=%@:%p children=%@ hasWindow=%d inHierarchy=%d frame=%@ bounds=%@ hidden=%d alpha=%.2f",
          context,
          NSStringFromClass(vc.class), vc,
          vc.parentViewController ? NSStringFromClass(vc.parentViewController.class) : @"nil", vc.parentViewController,
          childrenDesc,
          hasWindow, isInHierarchy, frameStr, boundsStr, hidden, alpha);

    if ([vc isKindOfClass:[UITabBarController class]]) {
        UITabBarController *tabBarVC = (UITabBarController *)vc;
        UIViewController *selected = tabBarVC.selectedViewController;
        NSUInteger selectedIndex = tabBarVC.selectedIndex;
        NSUInteger count = tabBarVC.viewControllers.count;
        NSUInteger tabsCount = 0;
        if (@available(iOS 18.0, *)) {
            tabsCount = tabBarVC.tabs.count;
        }
        NSLog(@"[HanlinHostDiag]   UITabBarController: selectedIndex=%lu count=%lu tabsCount=%lu selectedVC=%@:%p tabBarFrame=%@",
              (unsigned long)selectedIndex, (unsigned long)count, (unsigned long)tabsCount,
              selected ? NSStringFromClass(selected.class) : @"nil", selected,
              NSStringFromCGRect(tabBarVC.tabBar.frame));
        if (selected) {
            HanlinLogControllerHierarchy([NSString stringWithFormat:@"%@->selectedVC", context], selected);
        }
    } else if ([vc isKindOfClass:[UINavigationController class]]) {
        UINavigationController *navVC = (UINavigationController *)vc;
        UIViewController *top = navVC.topViewController;
        NSUInteger count = navVC.viewControllers.count;
        NSLog(@"[HanlinHostDiag]   UINavigationController: count=%lu topVC=%@:%p navBarHidden=%d navBarFrame=%@",
              (unsigned long)count,
              top ? NSStringFromClass(top.class) : @"nil", top,
              navVC.isNavigationBarHidden,
              NSStringFromCGRect(navVC.navigationBar.frame));
        if (top) {
            HanlinLogControllerHierarchy([NSString stringWithFormat:@"%@->topVC", context], top);
        }
    }
}

@interface HanlinNativeScriptContainerController ()
@property(nonatomic, weak, nullable) UIViewController *guestController;
@end

@implementation HanlinNativeScriptContainerController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    HanlinLogControllerHierarchy(@"Container.viewDidLoad", self);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    HanlinLogControllerHierarchy(@"Container.viewWillAppear", self);
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    HanlinLogControllerHierarchy(@"Container.viewDidAppear", self);
    if (self.guestController && self.guestController.isViewLoaded) {
        if (!CGRectEqualToRect(self.guestController.view.frame, self.view.bounds)) {
            self.guestController.view.frame = self.view.bounds;
            [self.guestController.view setNeedsLayout];
            [self.guestController.view layoutIfNeeded];
        }
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    HanlinLogControllerHierarchy(@"Container.viewWillDisappear", self);
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    HanlinLogControllerHierarchy(@"Container.viewDidDisappear", self);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (self.guestController && self.guestController.isViewLoaded) {
        CGRect targetFrame = self.view.bounds;
        if (!CGRectEqualToRect(self.guestController.view.frame, targetFrame)) {
            self.guestController.view.frame = targetFrame;
            [self.guestController.view setNeedsLayout];
            [self.guestController.view layoutIfNeeded];
        }
    }
    HanlinLogControllerHierarchy(@"Container.viewDidLayoutSubviews", self);
}

- (UIViewController *)childViewControllerForStatusBarStyle {
    return self.guestController ?: [super childViewControllerForStatusBarStyle];
}

- (UIViewController *)childViewControllerForStatusBarHidden {
    return self.guestController ?: [super childViewControllerForStatusBarHidden];
}

- (UIViewController *)childViewControllerForHomeIndicatorAutoHidden {
    return self.guestController ?: [super childViewControllerForHomeIndicatorAutoHidden];
}

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
    self.containerController.guestController = viewController;

    [self.containerController addChildViewController:viewController];
    viewController.view.frame = self.containerController.view.bounds;
    viewController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.containerController.view addSubview:viewController.view];
    [viewController didMoveToParentViewController:self.containerController];

    if (self.containerController.isViewLoaded && !CGRectIsEmpty(self.containerController.view.bounds)) {
        viewController.view.frame = self.containerController.view.bounds;
        [viewController.view setNeedsLayout];
        [viewController.view layoutIfNeeded];
    }

    HanlinLogControllerHierarchy(@"Presenter.presentNativeScriptApp", viewController);
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
    HanlinLogControllerHierarchy(@"Presenter.detachGuestController", guest);
    [guest willMoveToParentViewController:nil];
    [guest.view removeFromSuperview];
    [guest removeFromParentViewController];
    self.guestController = nil;
    self.containerController.guestController = nil;
}

@end

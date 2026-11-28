#include <UIKit/UIKit.h>

@protocol NativeScriptEmbedderDelegate
- (id)presentNativeScriptApp:(UIViewController *)viewController;
@end

@interface NativeScriptEmbedder : NSObject

@property(nonatomic, retain, readonly) id<NativeScriptEmbedderDelegate> delegate;
@property(nonatomic, retain, readonly) UIWindowScene *windowScene;

+ (NativeScriptEmbedder *)sharedInstance;
- (void)setDelegate:(id<NativeScriptEmbedderDelegate>)delegate;
- (void)setWindowScene:(UIWindowScene *)windowScene;
+ (void)setup;
+ (void)boot;

@end

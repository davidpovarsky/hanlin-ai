#import "NativeScriptUtils.h"

@implementation NativeScriptUtils

+ (UIFont *)getSystemFont:(CGFloat)size weight:(UIFontWeight)weight italic:(BOOL)italic symbolicTraits:(UIFontDescriptorSymbolicTraits)symbolicTraits {
    UIFont *result = [UIFont systemFontOfSize:size weight:weight];
    if (italic) {
        UIFontDescriptor *descriptor = [result.fontDescriptor fontDescriptorWithSymbolicTraits:symbolicTraits];
        if (descriptor) { result = [UIFont fontWithDescriptor:descriptor size:size]; }
    }
    return result;
}

+ (UIFont *)createUIFont:(NSDictionary *)font {
    CGFloat size = [font[@"fontSize"] floatValue];
    UIFontDescriptorSymbolicTraits symbolicTraits = 0;
    if ([font[@"isBold"] boolValue]) { symbolicTraits |= UIFontDescriptorTraitBold; }
    if ([font[@"isItalic"] boolValue]) { symbolicTraits |= UIFontDescriptorTraitItalic; }

    NSDictionary *traits = @{
        UIFontSymbolicTrait: @(symbolicTraits),
        UIFontWeightTrait: font[@"fontWeight"] ?: @(UIFontWeightRegular)
    };
    UIFont *result = nil;
    for (NSString *family in font[@"fontFamily"] ?: @[]) {
        NSString *resolvedFamily = family;
        if ([family.lowercaseString isEqualToString:@"serif"]) {
            resolvedFamily = @"Times New Roman";
        } else if ([family.lowercaseString isEqualToString:@"monospace"]) {
            resolvedFamily = @"Courier New";
        }
        if (resolvedFamily.length == 0 ||
            [resolvedFamily isEqualToString:@"sans-serif"] ||
            [resolvedFamily isEqualToString:@"system"]) {
            result = [self getSystemFont:size
                                  weight:[font[@"fontWeight"] floatValue]
                                  italic:[font[@"isItalic"] boolValue]
                          symbolicTraits:symbolicTraits];
            break;
        }
        UIFontDescriptor *descriptor = [UIFontDescriptor fontDescriptorWithFontAttributes:@{
            UIFontDescriptorFamilyAttribute: resolvedFamily,
            UIFontDescriptorTraitsAttribute: traits
        }];
        result = [UIFont fontWithDescriptor:descriptor size:size];
        if ([result.familyName isEqualToString:resolvedFamily]) { break; }
        result = nil;
    }
    return result ?: [self getSystemFont:size
                                    weight:[font[@"fontWeight"] floatValue]
                                    italic:[font[@"isItalic"] boolValue]
                            symbolicTraits:symbolicTraits];
}

+ (NSMutableAttributedString *)createMutableStringWithDetails:(NSDictionary *)details {
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    for (NSDictionary *detail in details[@"spans"] ?: @[]) {
        NSMutableAttributedString *span = [self createMutableStringForSpan:detail[@"text"] ?: @""
                                                                       font:detail[@"iosFont"]
                                                                      color:detail[@"color"]
                                                            backgroundColor:detail[@"backgroundColor"]
                                                             textDecoration:detail[@"textDecoration"]
                                                             baselineOffset:[detail[@"baselineOffset"] floatValue]];
        [result insertAttributedString:span atIndex:[detail[@"index"] unsignedIntegerValue]];
    }
    return result;
}

+ (NSMutableAttributedString *)createMutableStringForSpan:(NSString *)text
                                                      font:(UIFont *)font
                                                     color:(UIColor *)color
                                           backgroundColor:(UIColor *)backgroundColor
                                            textDecoration:(NSString *)textDecoration
                                            baselineOffset:(CGFloat)baselineOffset {
    NSMutableDictionary *attributes = [[NSMutableDictionary alloc] init];
    if (font) { attributes[NSFontAttributeName] = font; }
    if (color) { attributes[NSForegroundColorAttributeName] = color; }
    if (backgroundColor) { attributes[NSBackgroundColorAttributeName] = backgroundColor; }
    if ([textDecoration containsString:@"underline"]) {
        attributes[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
    }
    if ([textDecoration containsString:@"line-through"]) {
        attributes[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);
    }
    attributes[NSBaselineOffsetAttributeName] = @(baselineOffset);
    return [[NSMutableAttributedString alloc] initWithString:text attributes:attributes];
}

+ (UIImage *)scaleImage:(UIImage *)image width:(CGFloat)width height:(CGFloat)height scaleFactor:(CGFloat)scaleFactor {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = scaleFactor;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc]
        initWithSize:CGSizeMake(width, height)
        format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [image drawInRect:CGRectMake(0, 0, width, height)];
    }];
}

+ (NSData *)getImageData:(UIImage *)image format:(NSString *)format quality:(CGFloat)quality {
    if ([format.lowercaseString isEqualToString:@"png"]) { return UIImagePNGRepresentation(image); }
    return UIImageJPEGRepresentation(image, quality);
}

@end

#import "UIView+NativeScript.h"
#import "NativeScriptUtils.h"

@implementation UIView (NativeScript)

- (void)nativeScriptSetTextDecorationAndTransform:(NSString *)text textDecoration:(NSString *)textDecoration letterSpacing:(CGFloat)letterSpacing lineHeight:(CGFloat)lineHeight {
    NSMutableDictionary *attributes = [[NSMutableDictionary alloc] init];
    if ([textDecoration containsString:@"underline"]) {
        attributes[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
    }
    if ([textDecoration containsString:@"line-through"]) {
        attributes[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);
    }
    UIFont *font = nil;
    if ([self isKindOfClass:UITextView.class]) { font = ((UITextView *)self).font; }
    else if ([self isKindOfClass:UITextField.class]) { font = ((UITextField *)self).font; }
    else if ([self isKindOfClass:UILabel.class]) { font = ((UILabel *)self).font; }
    else if ([self isKindOfClass:UIButton.class]) { font = ((UIButton *)self).titleLabel.font; }
    if (letterSpacing != 0 && font) { attributes[NSKernAttributeName] = @(letterSpacing * font.pointSize); }
    if (lineHeight > 0) {
        NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
        style.lineSpacing = lineHeight;
        attributes[NSParagraphStyleAttributeName] = style;
    }
    NSAttributedString *result = [[NSAttributedString alloc] initWithString:text attributes:attributes];
    if ([self isKindOfClass:UIButton.class]) {
        [(UIButton *)self setAttributedTitle:result forState:UIControlStateNormal];
    } else if ([self isKindOfClass:UITextField.class]) {
        ((UITextField *)self).attributedText = result;
    } else if ([self isKindOfClass:UITextView.class]) {
        ((UITextView *)self).attributedText = result;
    } else if ([self isKindOfClass:UILabel.class]) {
        ((UILabel *)self).attributedText = result;
    }
}

- (void)nativeScriptSetFormattedTextDecorationAndTransform:(NSDictionary *)details letterSpacing:(CGFloat)letterSpacing lineHeight:(CGFloat)lineHeight {
    NSMutableAttributedString *result = [NativeScriptUtils createMutableStringWithDetails:details];
    NSRange range = NSMakeRange(0, result.length);
    if (letterSpacing != 0 && result.length > 0) {
        UIFont *font = [self isKindOfClass:UILabel.class] ? ((UILabel *)self).font : nil;
        [result addAttribute:NSKernAttributeName value:@(letterSpacing * font.pointSize) range:range];
    }
    if (lineHeight > 0 && result.length > 0) {
        NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
        style.lineSpacing = lineHeight;
        [result addAttribute:NSParagraphStyleAttributeName value:style range:range];
    }
    if ([self isKindOfClass:UIButton.class]) {
        [(UIButton *)self setAttributedTitle:result forState:UIControlStateNormal];
    } else if ([self isKindOfClass:UITextField.class]) {
        ((UITextField *)self).attributedText = result;
    } else if ([self isKindOfClass:UITextView.class]) {
        ((UITextView *)self).attributedText = result;
    } else if ([self isKindOfClass:UILabel.class]) {
        ((UILabel *)self).attributedText = result;
    }
}

- (void)nativeScriptSetFormattedTextStroke:(CGFloat)width color:(UIColor *)color {
    if (width <= 0 || ![self isKindOfClass:UILabel.class]) { return; }
    UILabel *label = (UILabel *)self;
    if (!label.attributedText) { return; }
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] initWithAttributedString:label.attributedText];
    NSRange range = NSMakeRange(0, result.length);
    [result addAttribute:NSStrokeWidthAttributeName value:@(width) range:range];
    [result addAttribute:NSStrokeColorAttributeName value:color range:range];
    label.attributedText = result;
}

@end

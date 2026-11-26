#if canImport(UIKit)
import SwiftUI
import UIKit
import HanlinPresentationKit

public struct HanlinImageViewer: View {
    private let image: UIImage
    @Binding private var isPresented: Bool
    private let saveImage: ((UIImage) -> Void)?
    private let copyImage: ((UIImage) -> Void)?

    public init(image: UIImage, isPresented: Binding<Bool>,
                saveImage: ((UIImage) -> Void)? = nil, copyImage: ((UIImage) -> Void)? = nil) {
        self.image = image; self._isPresented = isPresented
        self.saveImage = saveImage; self.copyImage = copyImage
    }
    @State private var isSaved: Bool = false    // 保存状态：true 表示保存成功
    @State private var isCopied: Bool = false   // 复制状态：true 表示复制成功

    // 缩放相关状态
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    // 平移相关状态
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geometry in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    // 应用缩放和平移效果
                    .scaleEffect(scale)
                    .offset(offset)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    // 组合“捏合缩放”和“拖拽平移”手势
                    .gesture(simultaneousGesture(in: geometry))
                    // 单击图片关闭浏览
                    .onTapGesture {
                        isPresented = false
                    }
            }

            // 底部操作按钮区域
            bottomButtons
        }
    }

    // 底部按钮视图
    private var bottomButtons: some View {
        VStack {
            Spacer()
            HStack(spacing: 6) {
                Spacer()

                // 复制按钮：状态依据 isCopied 切换图标
                if copyImage != nil {
                Button(action: copyImageToClipboard) {
                    Image(systemName: isCopied ? "checkmark.circle" : "square.on.square")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .bold()
                        .foregroundColor(isCopied ? Color(.systemGreen) : .white)
                        .padding(12)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCopied)
                }
                .background(
                    HanlinVisualEffectBlur(style: .systemThinMaterial)
                        .clipShape(Circle())
                        .shadow(color: .hanlinHLBlue, radius: 1)
                )
                .clipShape(Circle())
                .buttonStyle(.plain)
                .modifier(HanlinFeedbackModifier(.success, trigger: isCopied))

                }

                // 保存按钮：状态依据 isSaved 切换图标
                if saveImage != nil {
                Button(action: saveImageToPhotos) {
                    Image(systemName: isSaved ? "checkmark.circle" : "arrow.down")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .bold()
                        .foregroundColor(isSaved ? Color(.systemGreen) : .white)
                        .padding(12)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSaved)
                }
                .background(
                    HanlinVisualEffectBlur(style: .systemThinMaterial)
                        .clipShape(Circle())
                        .shadow(color: .hanlinHLBlue, radius: 1)
                )
                .clipShape(Circle())
                .buttonStyle(.plain)
                .modifier(HanlinFeedbackModifier(.success, trigger: isSaved))
                }
            }
            .padding(.horizontal)
        }
        .padding()
    }

    // 组合缩放与拖拽手势，并在拖拽时限制偏移范围
    private func simultaneousGesture(in geometry: GeometryProxy) -> some Gesture {
        let magnification = MagnificationGesture()
            .onChanged { value in
                self.scale = max(self.lastScale * value, 1.0)
                // 缩放时调整 offset，确保不超出可拖动范围
                self.offset = clampedOffset(proposed: self.lastOffset, in: geometry.size, scale: self.scale)
            }
            .onEnded { value in
                self.lastScale = self.scale
            }

        let drag = DragGesture()
            .onChanged { value in
                let proposed = CGSize(width: self.lastOffset.width + value.translation.width,
                                      height: self.lastOffset.height + value.translation.height)
                self.offset = clampedOffset(proposed: proposed, in: geometry.size, scale: self.scale)
            }
            .onEnded { _ in
                self.lastOffset = self.offset
            }

        return magnification.simultaneously(with: drag)
    }

    // 根据当前容器尺寸与缩放比例，计算允许的平移边界，并返回经过限制后的 offset
    private func clampedOffset(proposed: CGSize, in containerSize: CGSize, scale: CGFloat) -> CGSize {
        // 检查图片尺寸是否有效，防止除零错误和 IOSurface 错误
        guard image.size.width > 0 && image.size.height > 0 else {
            return CGSize.zero
        }

        // 计算图片的宽高比
        let imageAspect = image.size.width / image.size.height
        let containerAspect = containerSize.width / containerSize.height

        // 计算 scaledToFit 后图片在容器中的显示尺寸
        let displayedWidth: CGFloat
        let displayedHeight: CGFloat
        if imageAspect > containerAspect {
            displayedWidth = containerSize.width
            displayedHeight = containerSize.width / imageAspect
        } else {
            displayedHeight = containerSize.height
            displayedWidth = containerSize.height * imageAspect
        }

        // 乘以当前的缩放比例，得到最终图片尺寸
        let finalWidth = displayedWidth * scale
        let finalHeight = displayedHeight * scale

        // 计算平移边界，如果图片实际尺寸小于容器，则不可平移
        let maxOffsetX = max((finalWidth - containerSize.width) / 2, 0)
        let maxOffsetY = max((finalHeight - containerSize.height) / 2, 0)

        let clampedX = min(max(proposed.width, -maxOffsetX), maxOffsetX)
        let clampedY = min(max(proposed.height, -maxOffsetY), maxOffsetY)

        return CGSize(width: clampedX, height: clampedY)
    }

    // 保存图片到相册，点击后状态变为 true，2 秒后恢复
    private func saveImageToPhotos() {
        guard let saveImage else { return }
        saveImage(image)
        isSaved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { isSaved = false }
        }
    }

    // 复制图片到剪贴板，点击后状态变为 true，2 秒后恢复
    private func copyImageToClipboard() {
        guard let copyImage else { return }
        copyImage(image)
        isCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { isCopied = false }
        }
    }
}
#endif

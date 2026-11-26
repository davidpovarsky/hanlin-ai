/** Original UIKit image drawing, accessed through NativeScript's iOS metadata. */
export interface DrawingSize { readonly width: number; readonly height: number; }
export interface DrawingRect extends DrawingSize { readonly x: number; readonly y: number; }

const maximumOutputPixels = 16_000_000;

function checkedDimensions(size: DrawingSize, label: string): void {
  if (!Number.isFinite(size.width) || !Number.isFinite(size.height) ||
      size.width <= 0 || size.height <= 0 ||
      size.width > maximumOutputPixels / size.height) {
    throw new RangeError(`${label} must have finite positive dimensions within the image pixel budget.`);
  }
}

/** Draw clockwise around the destination rectangle's center, with transparent edges. */
export function drawImageInRect(
  image: UIImage, canvas: DrawingSize, rect: DrawingRect, rotationDegrees = 0
): UIImage {
  checkedDimensions(canvas, 'Canvas');
  checkedDimensions(rect, 'Image rectangle');
  if (![rect.x, rect.y, rotationDegrees, rect.x + rect.width / 2, rect.y + rect.height / 2].every(Number.isFinite)) {
    throw new RangeError('Image position and rotation must be finite.');
  }
  const format = UIGraphicsImageRendererFormat.defaultFormat();
  format.scale = 1;
  format.opaque = false;
  const renderer = UIGraphicsImageRenderer.alloc().initWithSizeFormat(CGSizeMake(canvas.width, canvas.height), format);
  return renderer.imageWithActions(context => {
    const graphics = context.CGContext;
    CGContextSaveGState(graphics);
    try {
      CGContextTranslateCTM(graphics, rect.x + rect.width / 2, rect.y + rect.height / 2);
      CGContextRotateCTM(graphics, (rotationDegrees % 360) * Math.PI / 180);
      image.drawInRect(CGRectMake(-rect.width / 2, -rect.height / 2, rect.width, rect.height));
    } finally {
      CGContextRestoreGState(graphics);
    }
  });
}

/** An asymmetric original native image makes rotation and the fixed center visible. */
export function drawingSource(): UIImage {
  const format = UIGraphicsImageRendererFormat.defaultFormat();
  format.scale = 1;
  const renderer = UIGraphicsImageRenderer.alloc().initWithSizeFormat(CGSizeMake(80, 40), format);
  return renderer.imageWithActions(context => {
    UIColor.systemRedColor.setFill();
    context.fillRect(CGRectMake(0, 0, 40, 40));
    UIColor.systemBlueColor.setFill();
    context.fillRect(CGRectMake(40, 0, 40, 40));
  });
}

/** Run inside the original native runtime; this is not a Node mock of UIKit. */
export function checkNativeDrawing(source: UIImage): { readonly rejectedInputs: number; readonly width: number; readonly height: number } {
  const canvas = {width: 128, height: 128};
  const rectangle = {x: 24, y: 44, width: 80, height: 40};
  const invalid: readonly (() => UIImage)[] = [
    () => drawImageInRect(source, {width: 0, height: 1}, rectangle),
    () => drawImageInRect(source, {width: -1, height: 1}, rectangle),
    () => drawImageInRect(source, {width: Number.NaN, height: 1}, rectangle),
    () => drawImageInRect(source, {width: Number.POSITIVE_INFINITY, height: 1}, rectangle),
    () => drawImageInRect(source, {width: 10_000, height: 10_000}, rectangle),
    () => drawImageInRect(source, canvas, {...rectangle, width: -1}),
    () => drawImageInRect(source, canvas, {...rectangle, x: Number.NaN}),
    () => drawImageInRect(source, canvas, rectangle, Number.POSITIVE_INFINITY)
  ];
  let rejectedInputs = 0;
  for (const draw of invalid) {
    try { draw(); }
    catch (error: unknown) {
      if (!(error instanceof RangeError)) throw error;
      rejectedInputs += 1;
    }
  }
  if (rejectedInputs !== invalid.length) throw new Error('An invalid drawing dimension reached the native renderer.');
  const rotated = drawImageInRect(source, canvas, rectangle, 90);
  if (rotated.size.width !== 128 || rotated.size.height !== 128 || rotated.scale !== 1) {
    throw new Error('The native renderer did not preserve the requested output size.');
  }
  return {rejectedInputs, width: rotated.size.width, height: rotated.size.height};
}

import { SubtleCrypto } from './SubtleCrypto';
const subtle = new SubtleCrypto();
export class Crypto {
    get subtle() {
        return subtle;
    }
    randomUUID() {
        if (__ANDROID__) {
            return org.nativescript.winter_tc.Crypto.randomUUID();
        }
        if (__IOS__) {
            return NSCCrypto.randomUUID();
        }
    }
    getRandomValues(typedArray) {
        // Both natives fill bytes, so a wider element type is reinterpreted over the very same
        // window — never past it, and never in place of the caller's own view, which is what
        // getRandomValues has to hand back.
        const bytes = typedArray.BYTES_PER_ELEMENT === 1 ? typedArray : new Uint8Array(typedArray.buffer, typedArray.byteOffset, typedArray.byteLength);
        if (__ANDROID__) {
            org.nativescript.winter_tc.Crypto.getRandomValues(bytes);
        }
        if (__IOS__) {
            // The pointer is V8-owned: freeWhenDone must stay NO, or Foundation and V8's
            // ArrayBufferSweeper both free the same allocation.
            const data = NSMutableData.dataWithBytesNoCopyLengthFreeWhenDone(bytes, bytes.byteLength, false);
            NSCCrypto.getRandomValues(data);
        }
        return typedArray;
    }
}
//# sourceMappingURL=index.js.map
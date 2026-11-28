const __ANDROID__ = globalThis.__ANDROID__ !== undefined ? globalThis.__ANDROID__ : false;
const __IOS__ = globalThis.__IOS__ !== undefined ? globalThis.__IOS__ : true;
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
            // The view goes to Security directly: the runtime hands over V8's backing store at
            // the view's byte offset, so the bytes land in the caller's array. No NSData may
            // sit in between — NSMutableData copies bytes it does not own, so a no-copy wrapper
            // fills a private copy, and one that owns them frees V8's allocation.
            const status = SecRandomCopyBytes(kSecRandomDefault, bytes.byteLength, bytes);
            if (status !== errSecSuccess) {
                throw new Error(`getRandomValues: SecRandomCopyBytes failed (${status})`);
            }
        }
        return typedArray;
    }
}
//# sourceMappingURL=index.js.map
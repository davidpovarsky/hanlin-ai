var _a, _b;
const parent_ = Symbol('[[parent]]');
const native_ = Symbol('[[native]]');
const algorithm_ = Symbol('[[algorithm]]');
const usages_ = Symbol('[[usages]]');
const extractable_ = Symbol('[[extractable]]');
const type_ = Symbol('[[type]]');
const privateKey_ = Symbol('[[privateKey]]');
const publicKey_ = Symbol('[[publicKey]]');
function parseHash(hash) {
    switch (hash) {
        case 'SHA-1':
            return 0;
        case 'SHA-256':
            return 1;
        case 'SHA-384':
            return 2;
        case 'SHA-512':
            return 3;
        default:
            return null;
    }
}
function parseUsages(usages) {
    const ret = NSMutableArray.new();
    if (Array.isArray(usages)) {
        /*

    kNSCCryptoDecrypt,
    kNSCCryptoEncrypt,
    kNSCCryptoSign,
    kNSCCryptoVerify,
    kNSCCryptoDeriveKey,
    kNSCCryptoDeriveBits,
    kNSCCryptoWrapKey,
    kNSCCryptoUnwrapKey,
*/
        for (const usage of usages) {
            switch (usage) {
                case 'encrypt':
                    ret.addObject(1);
                    break;
                case 'decrypt':
                    ret.addObject(0);
                    break;
                case 'sign':
                    ret.addObject(2);
                    break;
                case 'verify':
                    ret.addObject(3);
                    break;
                case 'deriveKey':
                    ret.addObject(4);
                    break;
                case 'deriveBits':
                    ret.addObject(5);
                    break;
                case 'wrapKey':
                    ret.addObject(6);
                    break;
                case 'unwrapKey':
                    ret.addObject(7);
                    break;
            }
        }
    }
    return ret;
}
export class CryptoKey {
    get algorithm() {
        return this[algorithm_];
    }
    get usages() {
        return this[usages_];
    }
    get extractable() {
        return this[extractable_];
    }
    get type() {
        return this[type_];
    }
    static fromNative(key) {
        if (key) {
            const ret = new CryptoKey();
            ret[native_] = key;
            return ret;
        }
        return null;
    }
}
export class CryptoKeyPair {
    constructor() {
        this[_a] = null;
        this[_b] = null;
    }
    get privateKey() {
        if (__IOS__) {
            const kp = this[native_];
            if (!this[privateKey_]) {
                this[privateKey_] = CryptoKey.fromNative(kp.privateKey);
            }
        }
        if (__ANDROID__) {
            const kp = this[native_];
            if (!this[privateKey_]) {
                this[privateKey_] = CryptoKey.fromNative(kp.getPrivate());
            }
        }
        return this[privateKey_];
    }
    get publicKey() {
        if (__IOS__) {
            const kp = this[native_];
            if (!this[publicKey_]) {
                this[publicKey_] = CryptoKey.fromNative(kp.publicKey);
            }
        }
        if (__ANDROID__) {
            const kp = this[native_];
            if (!this[publicKey_]) {
                this[publicKey_] = CryptoKey.fromNative(kp.getPublic());
            }
        }
        return this[publicKey_];
    }
    static fromNative(keyPair) {
        if (keyPair) {
            const ret = new CryptoKeyPair();
            ret[native_] = keyPair;
            return ret;
        }
        return null;
    }
}
_a = privateKey_, _b = publicKey_;
export class SubtleCrypto {
    digest(algorithm, data) {
        return new Promise((resolve, reject) => {
            let error;
            let mode;
            switch (algorithm) {
                case 'SHA-1':
                    mode = 0;
                    break;
                case 'SHA-256':
                    mode = 1;
                    break;
                case 'SHA-384':
                    mode = 2;
                    break;
                case 'SHA-512':
                    mode = 3;
                    break;
                default:
                    error = new Error('Operation is not supported');
                    break;
            }
            if (error !== undefined) {
                reject(error);
                return;
            }
            if (data instanceof ArrayBuffer || data instanceof Uint8Array || data instanceof Uint8ClampedArray) {
                // noop
            }
            else if (data?.BYTES_PER_ELEMENT !== 1) {
                data = new Uint8Array(data.buffer, data.byteOffset);
            }
            else {
                reject(new TypeError('Argument 2 could not be converted to any of: ArrayBufferView, ArrayBuffer.'));
                return;
            }
            if (__ANDROID__) {
                //const instance = java.security.MessageDigest.getInstance(algorithm);
                const buffer = org.nativescript.winter_tc.Crypto.digest(mode, data);
                const ab = ArrayBuffer.from(buffer);
                if (!ab) {
                    // todo throw failure
                }
                resolve(ab);
                /* instance.update(data as any);
                const digest = instance.digest();
    
                const ab = new ArrayBuffer(digest.length);
                (<any>org).nativescript.winter_tc.Utils.copyToBuffer(ab, digest);
    
                resolve(ab);

                */
            }
            if (__IOS__) {
                const d = NSData.dataWithData(data);
                NSCCrypto.digestModeCompletion(d, mode, (ab, error) => {
                    if (!ab) {
                        // todo throw failure
                    }
                    resolve(interop.bufferFromData(ab));
                });
                // const ab = NSCCrypto.digestMode(d, mode);
                // if (!ab) {
                // 	// todo throw failure
                // }
                // resolve(interop.bufferFromData(ab));
            }
        });
    }
    encrypt(algorithm, key, data) {
        return new Promise((resolve, reject) => {
            let error;
            switch (algorithm?.name) {
                case 'RSA-OAEP':
                    {
                        try {
                            if (__IOS__) {
                                const hash = parseHash(key.algorithm.hash.name);
                                const d = NSData.dataWithData(data);
                                NSCCrypto.encryptRsaKeyHashDataCompletion(key.type === 'private', key[parent_], hash, d, (ret, error) => {
                                    if (ret) {
                                        resolve(interop.bufferFromData(ret));
                                    }
                                    else {
                                        reject(new Error('Failed to encrypt data'));
                                    }
                                });
                            }
                            if (__ANDROID__) {
                                const hash = parseHash(key.algorithm.hash.name);
                                const ret = org.nativescript.winter_tc.Crypto.encryptRsaOAEP(key[parent_], hash, data);
                                if (ret) {
                                    resolve(ArrayBuffer.from(ret));
                                }
                                else {
                                    reject(new Error('Failed to encrypt data'));
                                }
                            }
                        }
                        catch (error) {
                            reject(error);
                        }
                    }
                    break;
                default:
                    error = new Error('Operation is not supported');
                    break;
            }
            if (error) {
                reject(error);
                return;
            }
        });
    }
    decrypt(algorithm, key, data) {
        return new Promise((resolve, reject) => {
            let error;
            switch (algorithm?.name) {
                case 'RSA-OAEP':
                    {
                        try {
                            if (__IOS__) {
                                const hash = parseHash(key.algorithm.hash.name);
                                const d = NSData.dataWithData(data);
                                NSCCrypto.decryptRsaKeyHashDataCompletion(key.type === 'private', key[parent_], hash, d, (ret, error) => {
                                    if (ret) {
                                        resolve(interop.bufferFromData(ret));
                                    }
                                    else {
                                        reject(new Error('Failed to decrypt data'));
                                    }
                                });
                            }
                            if (__ANDROID__) {
                                const hash = parseHash(key.algorithm.hash.name);
                                const ret = org.nativescript.winter_tc.Crypto.decryptRsaOAEP(key[parent_], hash, data);
                                if (ret) {
                                    resolve(ArrayBuffer.from(ret));
                                }
                                else {
                                    reject(new Error('Failed to decrypt data'));
                                }
                            }
                        }
                        catch (error) {
                            reject(error);
                        }
                    }
                    break;
                default:
                    error = new Error('Operation is not supported');
                    break;
            }
            if (error) {
                reject(error);
                return;
            }
        });
    }
    sign(algorithm, key, data) {
        return new Promise((resolve, reject) => {
            let error;
            const algorithmName = typeof algorithm === 'object' ? algorithm?.name : algorithm;
            switch (algorithmName) {
                case 'HMAC':
                    {
                        try {
                            if (__IOS__) {
                                const hash = parseHash(key.algorithm.hash.name);
                                const d = NSData.dataWithData(data);
                                const ret = NSCCrypto.signHmacHashData(key[native_], hash, d);
                                if (ret) {
                                    resolve(interop.bufferFromData(ret));
                                }
                                else {
                                    reject(new Error('Failed to sign data'));
                                }
                            }
                            if (__ANDROID__) {
                                let algo;
                                switch (key.algorithm.hash.name) {
                                    case 'SHA-1':
                                        algo = 'HmacSHA1';
                                        break;
                                    case 'SHA-256':
                                        algo = 'HmacSHA256';
                                        break;
                                    case 'SHA-384':
                                        algo = 'HmacSHA384';
                                        break;
                                    case 'SHA-512':
                                        algo = 'HmacSHA512';
                                        break;
                                    default:
                                        error = new Error('Operation is not supported');
                                        break;
                                }
                                if (error) {
                                    reject(error);
                                    return;
                                }
                                const ab = org.nativescript.winter_tc.Crypto.signHMAC(algo, key[native_], data);
                                resolve(ArrayBuffer.from(ab));
                            }
                        }
                        catch (error) {
                            reject(error);
                        }
                    }
                    break;
                default:
                    error = new Error('Operation is not supported');
                    break;
            }
            if (error) {
                reject(error);
                return;
            }
        });
    }
    verify(algorithm, key, signature, data) {
        return new Promise((resolve, reject) => {
            let error;
            const algorithmName = typeof algorithm === 'object' ? algorithm?.name : algorithm;
            switch (algorithmName) {
                case 'HMAC':
                    {
                        try {
                            if (__IOS__) {
                                const hash = parseHash(key.algorithm.hash.name);
                                const s = NSData.dataWithData(signature);
                                const d = NSData.dataWithData(data);
                                const ret = NSCCrypto.verifyHmacHashSignatureData(key[native_], hash, s, d);
                                resolve(ret);
                            }
                            if (__ANDROID__) {
                                let algo;
                                switch (key.algorithm.hash.name) {
                                    case 'SHA-1':
                                        algo = 'HmacSHA1';
                                        break;
                                    case 'SHA-256':
                                        algo = 'HmacSHA256';
                                        break;
                                    case 'SHA-384':
                                        algo = 'HmacSHA384';
                                        break;
                                    case 'SHA-512':
                                        algo = 'HmacSHA512';
                                        break;
                                    default:
                                        error = new Error('Operation is not supported');
                                        break;
                                }
                                if (error) {
                                    reject(error);
                                    return;
                                }
                                const ret = org.nativescript.winter_tc.Crypto.verifyHMAC(algo, key[native_], signature, data);
                                resolve(ret);
                            }
                        }
                        catch (error) {
                            reject(error);
                        }
                    }
                    break;
                default:
                    error = new Error('Operation is not supported');
                    break;
            }
            if (error) {
                reject(error);
                return;
            }
        });
    }
    generateKey(algorithm, extractable, keyUsages) {
        return new Promise((resolve, reject) => {
            const algorithmHash = typeof algorithm?.hash === 'object' ? algorithm?.hash?.name : algorithm.hash;
            switch (algorithm?.name) {
                case 'HMAC':
                    {
                        let algo;
                        let error;
                        switch (algorithmHash) {
                            case 'SHA-1':
                                algo = 'HmacSHA1';
                                break;
                            case 'SHA-256':
                                algo = 'HmacSHA256';
                                break;
                            case 'SHA-384':
                                algo = 'HmacSHA384';
                                break;
                            case 'SHA-512':
                                algo = 'HmacSHA512';
                                break;
                            default:
                                error = new Error('Operation is not supported');
                                break;
                        }
                        if (error) {
                            reject(error);
                            return;
                        }
                        if (__ANDROID__) {
                            // const mac = javax.crypto.KeyGenerator.getInstance(algo);
                            // const key = mac.generateKey();
                            const key = org.nativescript.winter_tc.Crypto.generateKeyHMAC(algo);
                            const ret = new CryptoKey();
                            ret[algorithm_] = { name: algorithm.name, hash: { name: algorithmHash } };
                            ret[native_] = key;
                            ret[usages_] = keyUsages;
                            ret[extractable_] = extractable;
                            ret[type_] = 'secret';
                            resolve(ret);
                        }
                        if (__IOS__) {
                            const hash = parseHash(algorithmHash);
                            const key = NSCCrypto.generateKeyHmacLength(hash, algorithm?.length ?? -1);
                            const ret = new CryptoKey();
                            ret[algorithm_] = { name: algorithm.name, hash: { name: algorithmHash } };
                            ret[native_] = key;
                            ret[usages_] = keyUsages;
                            ret[extractable_] = extractable;
                            ret[type_] = 'secret';
                            resolve(ret);
                        }
                    }
                    break;
                case 'RSA-OAEP':
                    {
                        if (__IOS__) {
                            const hash = parseHash(algorithm.hash);
                            if (hash === null) {
                                // todo throw invalid hash
                            }
                            const usages = parseUsages(keyUsages);
                            NSCCrypto.generateKeyRsaModulusLengthPublicExponentSizeHashExtractableKeyUsagesCompletion(2, algorithm.modulusLength, null, 0, hash, !!extractable, usages, (kp, error) => {
                                if (!kp) {
                                    reject(new Error('Failed to generateKey'));
                                }
                                else {
                                    const ret = CryptoKeyPair.fromNative(kp);
                                    ret.privateKey[parent_] = kp;
                                    ret.privateKey[algorithm_] = { name: algorithm.name, hash: { name: algorithm.hash }, modulusLength: algorithm.modulusLength, publicExponent: new Uint8Array([1, 0, 1]) };
                                    ret.privateKey[type_] = 'private';
                                    ret.privateKey[extractable_] = extractable;
                                    ret.publicKey[parent_] = kp;
                                    ret.publicKey[algorithm_] = { name: algorithm.name, hash: { name: algorithm.hash }, modulusLength: algorithm.modulusLength, publicExponent: new Uint8Array([1, 0, 1]) };
                                    ret.publicKey[type_] = 'public';
                                    ret.publicKey[extractable_] = extractable;
                                    resolve(ret);
                                }
                            });
                            /*
                            // ignore publicExponent for now
                            const kp = NSCCrypto.generateKeyRsaModulusLengthPublicExponentSizeHashExtractableKeyUsages(2, algorithm.modulusLength, null, 0, hash, !!extractable, usages);

                            if (!kp) {
                                reject(new Error('Failed to generateKey'));
                            } else {
                                const ret = CryptoKeyPair.fromNative(kp);
                                ret.privateKey[parent_] = kp;
                                ret.privateKey[algorithm_] = { name: algorithm.name, hash: { name: algorithm.hash }, modulusLength: algorithm.modulusLength, publicExponent: new Uint8Array([1, 0, 1]) };
                                ret.privateKey[type_] = 'private';
                                ret.privateKey[extractable_] = extractable;

                                ret.publicKey[parent_] = kp;
                                ret.publicKey[algorithm_] = { name: algorithm.name, hash: { name: algorithm.hash }, modulusLength: algorithm.modulusLength, publicExponent: new Uint8Array([1, 0, 1]) };
                                ret.publicKey[type_] = 'public';
                                ret.publicKey[extractable_] = extractable;

                                resolve(ret);
                            }
                            */
                        }
                        if (__ANDROID__) {
                            const hash = parseHash(algorithm.hash);
                            if (hash === null) {
                                // todo throw invalid hash
                            }
                            //	const usages = parseUsages(keyUsages);
                            // ignore publicExponent for now
                            const kp = org.nativescript.winter_tc.Crypto.generateKeyRsaOAEP(algorithm.modulusLength);
                            if (!kp) {
                                reject(new Error('Failed to generateKey'));
                            }
                            else {
                                const ret = CryptoKeyPair.fromNative(kp);
                                ret.privateKey[parent_] = kp;
                                ret.privateKey[algorithm_] = { name: algorithm.name, hash: { name: algorithm.hash }, modulusLength: algorithm.modulusLength, publicExponent: new Uint8Array([1, 0, 1]) };
                                ret.privateKey[type_] = 'private';
                                ret.privateKey[extractable_] = extractable;
                                ret.publicKey[parent_] = kp;
                                ret.publicKey[algorithm_] = { name: algorithm.name, hash: { name: algorithm.hash }, modulusLength: algorithm.modulusLength, publicExponent: new Uint8Array([1, 0, 1]) };
                                ret.publicKey[type_] = 'public';
                                ret.publicKey[extractable_] = extractable;
                                resolve(ret);
                            }
                        }
                    }
                    break;
                default:
                    reject(new Error(
                    // @ts-expect-error
                    `'subtle.generateKey()' is not implemented for ${algorithm?.name}.
						  Unrecognized algorithm name`));
                    break;
            }
        });
    }
}
//# sourceMappingURL=SubtleCrypto.js.map
#if canImport(CryptoKit) && canImport(Security)
import CryptoKit
import Foundation
import Security

/// OpenAI's official OSS Sign in with ChatGPT flow for locally hosted apps.
/// OAuth happens in the user's own browser; credentials remain on their device.
/// Hosts provide the required 127.0.0.1/auth/callback listener.
public enum HanlinChatGPTPlanError: Error, LocalizedError, Sendable {
    case invalidRedirect
    case denied
    case server(Int)
    case invalidToken
    case invalidIdentity
    case invalidAuthorization
    case unavailable

    public var errorDescription: String? {
        switch self {
        case .invalidRedirect: "The OpenAI sign-in callback is invalid."
        case .denied: "ChatGPT sign-in was declined."
        case .server(let status): "OpenAI authentication returned HTTP " + String(status)
        case .invalidToken: "OpenAI returned a token that could not be verified."
        case .invalidIdentity: "OpenAI identity could not be verified."
        case .invalidAuthorization: "OpenAI authorization is incomplete or expired."
        case .unavailable: "ChatGPT account access is unavailable. Use a supported API provider instead."
        }
    }
}

public struct HanlinChatGPTAuthorizationAttempt: Sendable {
    public let url: URL
    public let redirectURI: URL
    public let clientID: String
    public let state: String
    public let nonce: String
    public let verifier: String

    public init(url:URL,redirectURI:URL,clientID:String,state:String,
                nonce:String,verifier:String) {
        self.url=url
        self.redirectURI=redirectURI
        self.clientID=clientID
        self.state=state
        self.nonce=nonce
        self.verifier=verifier
    }
}

public struct HanlinChatGPTPlanCredentials: Codable, Sendable {
    public let clientID: String
    public let hostID: String
    public let subject: String
    public let email: String?
    public let idToken: String
    public let accessToken: String
    public let refreshToken: String
    public let scopes: [String]
    public let expiresAt: Date

    public var canUsePlan: Bool {
        scopes.contains("chatgpt.tokens.use.direct") &&
        scopes.contains("resource.invoke")
    }
}

public struct HanlinChatGPTPlanModel: Codable, Sendable, Identifiable {
    public var id: String { slug }
    public let slug: String
    public let displayName: String
    public let visibility: String?

    private enum CodingKeys: String, CodingKey {
        case slug,visibility
        case displayName = "display_name"
    }
}

/// The shared Hanlin implementation is deliberately separate from a Lorvex
/// account: an OpenAI credential never grants access to Lorvex task data.
/// ChatGPT plan usage requires a granted Responses scope. No ChatGPT cookies,
/// conversation data or OpenAI API key is collected.
public actor HanlinChatGPTPlanClient {
    private static let issuer = "https://auth.openai.com"
    private static let tokenURL = URL(string: "https://auth.openai.com/api/accounts/oauth/token")!
    private static let jwksURL = URL(string: "https://auth.openai.com/.well-known/jwks.json")!
    private static let resource = "https://api.openai.com/v1"

    public init() {}

    public static func makeHostID() -> String {
        "urn:uuid:" + UUID().uuidString.lowercased()
    }

    private static func random() throws -> String {
        var bytes=[UInt8](repeating:0,count:32)
        guard SecRandomCopyBytes(kSecRandomDefault,bytes.count,&bytes)==errSecSuccess else {
            throw HanlinChatGPTPlanError.unavailable
        }
        return Data(bytes).base64URLEncodedString()
    }

    public static func makeAttempt(
        hostID: String, loopbackPort: UInt16, previous: HanlinChatGPTPlanCredentials? = nil
    ) throws -> HanlinChatGPTAuthorizationAttempt {
        guard hostID.hasPrefix("urn:uuid:"),loopbackPort>0 else {
            throw HanlinChatGPTPlanError.invalidAuthorization
        }
        let verifier=try random()+random()
        let nonce=try random()
        let state=try random()
        let client=previous?.clientID ?? "dynamic_agent_client"
        let redirect=URL(string:
            "http://127.0.0.1:" + String(loopbackPort) + "/auth/callback")!
        var components=URLComponents(string:
            "https://auth.openai.com/api/accounts/authorize")!
        var params=[
            URLQueryItem(name:"client_id",value:client),
            URLQueryItem(name:"ext_agent_host_id",value:hostID),
            URLQueryItem(name:"redirect_uri",value:redirect.absoluteString),
            URLQueryItem(name:"response_type",value:"code"),
            URLQueryItem(name:"scope",value:
                "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"),
            URLQueryItem(name:"resource",value:resource),
            URLQueryItem(name:"state",value:state),
            URLQueryItem(name:"nonce",value:nonce),
            URLQueryItem(name:"code_challenge_method",value:"S256"),
            URLQueryItem(name:"code_challenge",value:
                Data(SHA256.hash(data:Data(verifier.utf8))).base64URLEncodedString())
        ]
        if previous==nil {
            params.append(URLQueryItem(name:"agent_name_hint",value:"Lorvex AI"))
        } else {
            params.append(URLQueryItem(name:"id_token_hint",value:previous!.idToken))
            if let email=previous?.email {
                params.append(URLQueryItem(name:"login_hint",value:email))
            }
        }
        components.queryItems=params
        guard let url=components.url else {
            throw HanlinChatGPTPlanError.invalidAuthorization
        }
        return .init(url:url,redirectURI:redirect,clientID:client,
                     state:state,nonce:nonce,verifier:verifier)
    }

    private struct TokenResponse: Decodable {
        var access_token: String
        var refresh_token: String?
        var id_token: String?
        var expires_in: Int
        var scope: String?
    }
    private struct JWKS: Decodable {
        struct Key: Decodable {
            let kid: String
            let kty: String
            let alg: String?
            let n: String?
            let e: String?
            let x: String?
            let y: String?
            let crv: String?
        }
        let keys: [Key]
    }

    private static func tokenRequest(_ params:[String:String]) async throws -> TokenResponse {
        var request=URLRequest(url:tokenURL)
        request.httpMethod="POST"
        request.timeoutInterval=25
        request.setValue("application/x-www-form-urlencoded",
                         forHTTPHeaderField:"Content-Type")
        var form=URLComponents()
        form.queryItems=params.map { URLQueryItem(name:$0.key,value:$0.value) }
        request.httpBody=Data((form.percentEncodedQuery ?? "").utf8)
        let (bytes,response)=try await URLSession.shared.data(for:request)
        guard let response=response as? HTTPURLResponse else {
            throw HanlinChatGPTPlanError.invalidToken
        }
        guard response.statusCode==200 else {
            throw HanlinChatGPTPlanError.server(response.statusCode)
        }
        let result=try JSONDecoder().decode(TokenResponse.self,from:bytes)
        guard !result.access_token.isEmpty,result.expires_in>0 else {
            throw HanlinChatGPTPlanError.invalidToken
        }
        return result
    }

    public func exchange(
        callback: URL,attempt: HanlinChatGPTAuthorizationAttempt,
        priorAccount: HanlinChatGPTPlanCredentials? = nil
    ) async throws -> HanlinChatGPTPlanCredentials {
        guard callback.scheme=="http",callback.host=="127.0.0.1",
              callback.port==attempt.redirectURI.port,
              callback.path=="/auth/callback" else {
            throw HanlinChatGPTPlanError.invalidRedirect
        }
        let q=URLComponents(url:callback,resolvingAgainstBaseURL:false)?.queryItems ?? []
        let params=Dictionary(q.compactMap { item -> (String,String)? in
            item.value.map { (item.name,$0) }
        },uniquingKeysWith:{old,_ in old})
        guard params["state"]==attempt.state else {
            throw HanlinChatGPTPlanError.invalidAuthorization
        }
        if params["error"] != nil { throw HanlinChatGPTPlanError.denied }
        guard let code=params["code"],!code.isEmpty else {
            throw HanlinChatGPTPlanError.invalidAuthorization
        }
        let issuedID=params["client_id"] ?? (priorAccount?.clientID ?? "")
        guard !issuedID.isEmpty,issuedID != "dynamic_agent_client" else {
            throw HanlinChatGPTPlanError.invalidAuthorization
        }
        if let priorAccount,issuedID != priorAccount.clientID {
            throw HanlinChatGPTPlanError.invalidIdentity
        }
        let response=try await Self.tokenRequest([
            "grant_type":"authorization_code",
            "client_id":issuedID,
            "code":code,
            "code_verifier":attempt.verifier,
            "redirect_uri":attempt.redirectURI.absoluteString,
            "resource":Self.resource
        ])
        guard let idToken=response.id_token,let refresh=response.refresh_token else {
            throw HanlinChatGPTPlanError.invalidToken
        }
        let claims=try await Self.verifyIdentity(idToken,
            clientID:issuedID,nonce:attempt.nonce,accessToken:response.access_token)
        if let priorAccount,claims.subject != priorAccount.subject {
            throw HanlinChatGPTPlanError.invalidIdentity
        }
        return HanlinChatGPTPlanCredentials(
            clientID:issuedID,hostID:priorAccount?.hostID ??
                (URLComponents(url:attempt.url,resolvingAgainstBaseURL:false)?
                   .queryItems?.first(where:{$0.name=="ext_agent_host_id"})?.value ?? ""),
            subject:claims.subject,email:claims.email,idToken:idToken,
            accessToken:response.access_token,refreshToken:refresh,
            scopes:(response.scope ?? "").split(separator:" ").map(String.init),
            expiresAt:Date().addingTimeInterval(TimeInterval(response.expires_in)))
    }

    public func refresh(_ account:HanlinChatGPTPlanCredentials) async throws
      -> HanlinChatGPTPlanCredentials {
        let result=try await Self.tokenRequest([
            "grant_type":"refresh_token","client_id":account.clientID,
            "refresh_token":account.refreshToken,"resource":Self.resource
        ])
        return .init(clientID:account.clientID,hostID:account.hostID,
                     subject:account.subject,email:account.email,
                     idToken:result.id_token ?? account.idToken,
                     accessToken:result.access_token,
                     refreshToken:result.refresh_token ?? account.refreshToken,
                     scopes:result.scope.map{$0.split(separator:" ").map(String.init)} ??
                         account.scopes,
                     expiresAt:Date().addingTimeInterval(TimeInterval(result.expires_in)))
    }

    public func listModels(accessToken:String) async throws -> [HanlinChatGPTPlanModel] {
        var request=URLRequest(url:URL(string:"https://api.openai.com/v1/models")!)
        request.setValue("Bearer "+accessToken,forHTTPHeaderField:"Authorization")
        request.timeoutInterval=25
        let (data,response)=try await URLSession.shared.data(for:request)
        guard let response=response as? HTTPURLResponse,response.statusCode==200 else {
            throw HanlinChatGPTPlanError.unavailable
        }
        struct Catalog: Decodable { let models:[HanlinChatGPTPlanModel] }
        return try JSONDecoder().decode(Catalog.self,from:data).models
            .filter{$0.visibility=="list"}
    }

    private struct Identity {let subject:String;let email:String?}
    private static func verifyIdentity(_ jwt:String,clientID:String,
        nonce:String,accessToken:String) async throws -> Identity {
        let parts=jwt.split(separator:".")
        guard parts.count==3,
              let headerBytes=Data(base64URLString:String(parts[0])),
              let claimsBytes=Data(base64URLString:String(parts[1])),
              let signature=Data(base64URLString:String(parts[2])),
              let header=try? JSONSerialization.jsonObject(with:headerBytes)
                  as? [String:Any],
              let payload=try? JSONSerialization.jsonObject(with:claimsBytes)
                  as? [String:Any],
              let kid=header["kid"] as? String,
              let alg=header["alg"] as? String,
              ["RS256","ES256"].contains(alg)
        else { throw HanlinChatGPTPlanError.invalidToken }
        let (jwksBytes,jwksResponse)=try await URLSession.shared.data(from:jwksURL)
        guard (jwksResponse as? HTTPURLResponse)?.statusCode==200,
              let keys=try? JSONDecoder().decode(JWKS.self,from:jwksBytes),
              let jwk=keys.keys.first(where:{$0.kid==kid}) else {
            throw HanlinChatGPTPlanError.invalidToken
        }
        let signing=Data((String(parts[0])+"."+String(parts[1])).utf8)
        let verified:Bool
        if alg=="RS256",jwk.kty=="RSA",let n=jwk.n,let e=jwk.e,
           let modulus=Data(base64URLString:n),let exponent=Data(base64URLString:e){
            let pkcs1=asn1(tag:0x30,asn1Integer(modulus)+asn1Integer(exponent))
            let key=SecKeyCreateWithData(pkcs1 as CFData,[
                kSecAttrKeyType:kSecAttrKeyTypeRSA,
                kSecAttrKeyClass:kSecAttrKeyClassPublic,
                kSecAttrKeySizeInBits:(modulus.count*8)
            ] as CFDictionary,nil)
            verified=key.map{
                SecKeyVerifySignature($0,.rsaSignatureMessagePKCS1v15SHA256,
                                      signing as CFData,signature as CFData,nil)
            } ?? false
        } else if alg=="ES256",jwk.kty=="EC",jwk.crv=="P-256",
                  let x=jwk.x,let y=jwk.y,
                  let xb=Data(base64URLString:x),let yb=Data(base64URLString:y),
                  let key=try? P256.Signing.PublicKey(x963Representation:
                    Data([0x04])+xb+yb),
                  let sig=try? P256.Signing.ECDSASignature(rawRepresentation:signature) {
            verified=key.isValidSignature(sig,for:signing)
        } else { verified=false }
        guard verified,
              payload["iss"] as? String == issuer,
              let subject=payload["sub"] as? String,!subject.isEmpty,
              payload["nonce"] as? String == nonce,
              let exp=payload["exp"] as? TimeInterval,
              exp > Date().timeIntervalSince1970-60
        else {throw HanlinChatGPTPlanError.invalidIdentity}
        if let aud=payload["aud"] as? String {
            guard aud==clientID else{throw HanlinChatGPTPlanError.invalidIdentity}
        } else if let aud=payload["aud"] as? [String] {
            guard aud.contains(clientID) else {
                throw HanlinChatGPTPlanError.invalidIdentity
            }
        } else { throw HanlinChatGPTPlanError.invalidIdentity }
        if let atHash=payload["at_hash"] as? String {
            let digest=Data(SHA256.hash(data:Data(accessToken.utf8)))
            guard digest.prefix(digest.count/2).base64URLEncodedString()==atHash else {
                throw HanlinChatGPTPlanError.invalidIdentity
            }
        }
        let validEmail=payload["email_verified"] as? Bool == true
        return Identity(subject:subject,email:validEmail ? payload["email"] as? String : nil)
    }

    private static func asn1Length(_ length:Int) -> Data {
        if length<128 {return Data([UInt8(length)])}
        if length<256 {return Data([0x81,UInt8(length)])}
        if length<65536 {return Data([0x82,UInt8(length>>8),UInt8(length&255)])}
        return Data([0x83,UInt8(length>>16),UInt8((length>>8)&255),UInt8(length&255)])
    }
    private static func asn1(tag:UInt8,_ body:Data)->Data {
        Data([tag])+asn1Length(body.count)+body
    }
    private static func asn1Integer(_ data:Data)->Data {
        var bytes=Data(data.drop(while:{$0==0}))
        if bytes.isEmpty {bytes=Data([0])}
        if bytes.first!>=128 {bytes.insert(0,at:0)}
        return asn1(tag:0x02,bytes)
    }
}

private extension Data {
    init?(base64URLString:String) {
        var str=base64URLString.replacingOccurrences(of:"-",with:"+")
                                 .replacingOccurrences(of:"_",with:"/")
        str += String(repeating:"=",count:(4-str.count%4)%4)
        guard let data=Data(base64Encoded:str) else {return nil}
        self=data
    }
    func base64URLEncodedString()->String {
        base64EncodedString().replacingOccurrences(of:"+",with:"-")
                             .replacingOccurrences(of:"/",with:"_")
                             .replacingOccurrences(of:"=",with:"")
    }
}
#endif

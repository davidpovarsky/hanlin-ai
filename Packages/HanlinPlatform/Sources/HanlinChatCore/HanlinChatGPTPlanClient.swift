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
    case oauth(status: Int, code: String?, requestID: String?)
    case invalidToken
    case invalidIdentity
    case invalidAuthorization
    case unavailable

    public var errorDescription: String? {
        switch self {
        case .invalidRedirect: "The OpenAI sign-in callback is invalid."
        case .denied: "ChatGPT sign-in was declined."
        case .server(let status): "OpenAI authentication returned HTTP " + String(status)
        case .oauth(let status, let code, let requestID):
            "OpenAI request failed (HTTP \(status), code: \(code ?? "unknown"), request: \(requestID ?? "unavailable"))."
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
    public let expectedSubject: String?

    public init(url:URL,redirectURI:URL,clientID:String,state:String,
                nonce:String,verifier:String,expectedSubject:String? = nil) {
        self.url=url
        self.redirectURI=redirectURI
        self.clientID=clientID
        self.state=state
        self.nonce=nonce
        self.verifier=verifier
        self.expectedSubject=expectedSubject
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
    public let earliestRefreshAt: Date?

    public init(clientID: String, hostID: String, subject: String, email: String?,
                idToken: String, accessToken: String, refreshToken: String,
                scopes: [String], expiresAt: Date, earliestRefreshAt: Date? = nil) {
        self.clientID = clientID; self.hostID = hostID; self.subject = subject
        self.email = email; self.idToken = idToken; self.accessToken = accessToken
        self.refreshToken = refreshToken; self.scopes = scopes
        self.expiresAt = expiresAt; self.earliestRefreshAt = earliestRefreshAt
    }

    public var canUsePlan: Bool {
        scopes.contains("chatgpt.tokens.use.direct") &&
        scopes.contains("resource.invoke")
    }
}

/// Non-secret account registration metadata retained after local sign-out.
/// Client ID plus verified subject separates registrations even for one email.
public struct HanlinChatGPTPlanRegistration: Codable, Sendable, Hashable, Identifiable {
    public var id: String { clientID }
    public let clientID: String
    public let subject: String
    public let email: String?

    public init(credentials: HanlinChatGPTPlanCredentials) {
        clientID = credentials.clientID
        subject = credentials.subject
        email = credentials.email
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

    private var refreshes: [String: Task<HanlinChatGPTPlanCredentials, Error>] = [:]
    private var refreshed: [String: HanlinChatGPTPlanCredentials] = [:]
    private var revokedRefreshes = Set<String>()
    private var revocationTargets: [String: HanlinChatGPTPlanCredentials] = [:]
    private var completedRevocations = Set<String>()
    private var staleRevocationSources = Set<String>()

    private let session: URLSession

    private let now: @Sendable () -> Date

    public init(session: URLSession = .shared, now: @escaping @Sendable () -> Date = { Date() }) {
        self.session = session
        self.now = now
    }

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
        hostID: String, loopbackPort: UInt16, previous: HanlinChatGPTPlanCredentials? = nil,
        appName: String = "Hanlin AI",
        registration: HanlinChatGPTPlanRegistration? = nil,
        clientID: String? = nil, idTokenHint: String? = nil, emailHint: String? = nil,
        requestPlanConsent: Bool = false
    ) throws -> HanlinChatGPTAuthorizationAttempt {
        guard hostID.hasPrefix("urn:uuid:"),
              UUID(uuidString: String(hostID.dropFirst("urn:uuid:".count))) != nil,
              loopbackPort > 0, !appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HanlinChatGPTPlanError.invalidAuthorization
        }
        if let previous, let registration,
           (previous.clientID != registration.clientID || previous.subject != registration.subject) {
            throw HanlinChatGPTPlanError.invalidIdentity
        }
        if let registration,
           (registration.clientID.isEmpty || registration.clientID == "dynamic_agent_client" || registration.subject.isEmpty) {
            throw HanlinChatGPTPlanError.invalidIdentity
        }
        if let previous, previous.hostID != hostID {
            throw HanlinChatGPTPlanError.invalidIdentity
        }
        if let clientID {
            guard !clientID.isEmpty,
                  previous.map({ $0.clientID == clientID }) ?? true,
                  registration.map({ $0.clientID == clientID }) ?? true else {
                throw HanlinChatGPTPlanError.invalidIdentity
            }
        }
        let verifier=try random()+random()
        let nonce=try random()
        let state=try random()
        let client=previous?.clientID ?? registration?.clientID ?? clientID ?? "dynamic_agent_client"
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
        if client == "dynamic_agent_client" {
            params.append(URLQueryItem(name:"agent_name_hint",value:appName))
        } else {
            if let idToken = previous?.idToken ?? idTokenHint, !idToken.isEmpty {
                params.append(URLQueryItem(name:"id_token_hint",value:idToken))
            }
            if let email = previous?.email ?? registration?.email ?? emailHint, !email.isEmpty {
                params.append(URLQueryItem(name:"login_hint",value:email))
            }
        }
        if requestPlanConsent { params.append(URLQueryItem(name: "prompt", value: "consent")) }
        components.queryItems=params
        guard let url=components.url else {
            throw HanlinChatGPTPlanError.invalidAuthorization
        }
        return .init(url:url,redirectURI:redirect,clientID:client,
                     state:state,nonce:nonce,verifier:verifier,
                     expectedSubject: previous?.subject ?? registration?.subject)
    }

    private struct TokenResponse: Decodable, Sendable {
        var access_token: String
        var refresh_token: String?
        var id_token: String?
        var expires_in: Int
        var scope: String?
        var token_type: String
        var earliest_refresh_at: TokenDate?
    }
    private struct TokenDate: Decodable, Sendable {
        let value: Date
        init(from decoder: any Decoder) throws {
            let box = try decoder.singleValueContainer()
            if let seconds = try? box.decode(Double.self), seconds.isFinite {
                value = Date(timeIntervalSince1970: seconds)
                return
            }
            let raw = try box.decode(String.self)
            if let seconds = Double(raw), seconds.isFinite {
                value = Date(timeIntervalSince1970: seconds)
            } else if let date = ISO8601DateFormatter().date(from: raw) {
                value = date
            } else {
                throw DecodingError.dataCorruptedError(in: box, debugDescription: "Invalid token timestamp")
            }
        }
    }
    private struct JWKS: Decodable, Sendable {
        struct Key: Decodable, Sendable {
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

    private static func tokenRequest(_ params:[String:String], session: URLSession) async throws -> TokenResponse {
        var request=URLRequest(url:tokenURL)
        request.httpMethod="POST"
        request.timeoutInterval=25
        request.setValue("application/x-www-form-urlencoded",
                         forHTTPHeaderField:"Content-Type")
        var form=URLComponents()
        form.queryItems=params.map { URLQueryItem(name:$0.key,value:$0.value) }
        request.httpBody=Data(((form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B")).utf8)
        let (bytes,response)=try await session.data(for:request)
        guard let response=response as? HTTPURLResponse else {
            throw HanlinChatGPTPlanError.invalidToken
        }
        guard response.statusCode==200 else {
            throw serviceError(bytes, response: response)
        }
        let result=try JSONDecoder().decode(TokenResponse.self,from:bytes)
        guard !result.access_token.isEmpty,result.expires_in>0,
              result.token_type.caseInsensitiveCompare("Bearer") == .orderedSame else {
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
              callback.path=="/auth/callback", callback.user == nil,
              callback.password == nil, callback.fragment == nil else {
            throw HanlinChatGPTPlanError.invalidRedirect
        }
        let q=URLComponents(url:callback,resolvingAgainstBaseURL:false)?.queryItems ?? []
        var params: [String: String] = [:]
        for item in q {
            guard params[item.name] == nil, let value = item.value else {
                throw HanlinChatGPTPlanError.invalidAuthorization
            }
            params[item.name] = value
        }
        guard params["state"]==attempt.state else {
            throw HanlinChatGPTPlanError.invalidAuthorization
        }
        if let code = params["error"] {
            if code == "access_denied" { throw HanlinChatGPTPlanError.denied }
            throw HanlinChatGPTPlanError.oauth(status: 0, code: code, requestID: nil)
        }
        guard let code=params["code"],!code.isEmpty else {
            throw HanlinChatGPTPlanError.invalidAuthorization
        }
        let issuedID = params["client_id"] ??
            (attempt.clientID == "dynamic_agent_client" ? "" : attempt.clientID)
        guard !issuedID.isEmpty,issuedID != "dynamic_agent_client" else {
            throw HanlinChatGPTPlanError.invalidAuthorization
        }
        if attempt.clientID != "dynamic_agent_client", issuedID != attempt.clientID {
            throw HanlinChatGPTPlanError.invalidIdentity
        }
        if let priorAccount, issuedID != priorAccount.clientID {
            throw HanlinChatGPTPlanError.invalidIdentity
        }
        let response=try await Self.tokenRequest([
            "grant_type":"authorization_code",
            "client_id":issuedID,
            "code":code,
            "code_verifier":attempt.verifier,
            "redirect_uri":attempt.redirectURI.absoluteString,
            "resource":Self.resource
        ], session: session)
        guard let idToken=response.id_token, !idToken.isEmpty,
              let refresh=response.refresh_token, !refresh.isEmpty else {
            throw HanlinChatGPTPlanError.invalidToken
        }
        let claims=try await Self.verifyIdentity(idToken,
            clientID:issuedID,nonce:attempt.nonce,accessToken:response.access_token, session: session, now: now)
        if let expected = attempt.expectedSubject, claims.subject != expected {
            throw HanlinChatGPTPlanError.invalidIdentity
        }
        if let priorAccount,claims.subject != priorAccount.subject {
            throw HanlinChatGPTPlanError.invalidIdentity
        }
        return HanlinChatGPTPlanCredentials(
            clientID:issuedID,hostID:
                (URLComponents(url:attempt.url,resolvingAgainstBaseURL:false)?
                   .queryItems?.first(where:{$0.name=="ext_agent_host_id"})?.value ?? ""),
            subject:claims.subject,email:claims.email,idToken:idToken,
            accessToken:response.access_token,refreshToken:refresh,
            scopes:(response.scope ?? "").split(separator:" ").map(String.init),
            expiresAt:now().addingTimeInterval(TimeInterval(response.expires_in)),
            earliestRefreshAt:response.earliest_refresh_at?.value)
    }

    /// All waiters for a rotating token share one request, including callers
    /// which still hold the previous credential snapshot after a refresh.
    public func refresh(_ account: HanlinChatGPTPlanCredentials) async throws
      -> HanlinChatGPTPlanCredentials {
        guard !account.clientID.isEmpty, account.clientID != "dynamic_agent_client",
              !account.refreshToken.isEmpty else {
            throw HanlinChatGPTPlanError.invalidAuthorization
        }
        let key = Self.refreshKey(account)
        guard !revokedRefreshes.contains(key) else { throw HanlinChatGPTPlanError.invalidAuthorization }
        if let value = refreshed[key], value.expiresAt > now() { return value }
        let pending: Task<HanlinChatGPTPlanCredentials, Error>
        if let existing = refreshes[key] { pending = existing }
        else {
            pending = Task { try await Self.refreshAccount(account, session: session, now: now) }
            refreshes[key] = pending
        }
        do {
            let value = try await pending.value
            guard !revokedRefreshes.contains(key) else { throw CancellationError() }
            refreshes[key] = nil
            refreshed = refreshed.filter { $0.value.clientID != account.clientID }
            refreshed[key] = value
            return value
        } catch {
            refreshes[key] = nil
            throw error
        }
    }

    private static func refreshKey(_ account: HanlinChatGPTPlanCredentials) -> String {
        account.clientID + ":" + account.subject + ":" +
            Data(SHA256.hash(data: Data(account.refreshToken.utf8))).base64URLEncodedString()
    }

    private static func refreshAccount(_ account: HanlinChatGPTPlanCredentials, session: URLSession,
                                       now: @Sendable () -> Date) async throws
      -> HanlinChatGPTPlanCredentials {
        let result = try await tokenRequest([
            "grant_type": "refresh_token", "client_id": account.clientID,
            "refresh_token": account.refreshToken, "resource": resource
        ], session: session)
        var email = account.email
        if let idToken = result.id_token {
            let identity = try await verifyIdentity(idToken, clientID: account.clientID,
                nonce: nil, accessToken: result.access_token, session: session, now: now)
            guard identity.subject == account.subject else {
                throw HanlinChatGPTPlanError.invalidIdentity
            }
            email = identity.email
        }
        guard let refreshToken = result.refresh_token, !refreshToken.isEmpty else {
            throw HanlinChatGPTPlanError.invalidToken
        }
        return .init(clientID: account.clientID, hostID: account.hostID,
            subject: account.subject, email: email,
            idToken: result.id_token ?? account.idToken,
            accessToken: result.access_token, refreshToken: refreshToken,
            scopes: result.scope.map { $0.split(separator: " ").map(String.init) } ?? account.scopes,
            expiresAt: now().addingTimeInterval(TimeInterval(result.expires_in)),
            earliestRefreshAt: result.earliest_refresh_at?.value)
    }

    /// Attempts remote revocation. Hosts clear local tokens even if this throws,
    /// and disclose that remote revocation could not be confirmed.
    public func revoke(_ supplied: HanlinChatGPTPlanCredentials) async throws {
        guard !supplied.clientID.isEmpty, supplied.clientID != "dynamic_agent_client",
              !supplied.refreshToken.isEmpty else { throw HanlinChatGPTPlanError.invalidAuthorization }
        let key = Self.refreshKey(supplied)
        if completedRevocations.contains(key) { return }
        revokedRefreshes.insert(key)
        var account = supplied
        if let pending = revocationTargets[key] { account = pending }
        else {
            // Once a rotated source failed to revoke, never claim success by
            // sending its obsolete token after the replacement was discarded.
            guard !staleRevocationSources.contains(key) else {
                throw HanlinChatGPTPlanError.invalidAuthorization
            }
            if let latest = refreshed[key] { account = latest }
            else if let pending = refreshes[key], let latest = try? await pending.value { account = latest }
        }
        let targetKey = Self.refreshKey(account)
        if targetKey != key { staleRevocationSources.insert(key) }
        let sessionKeys: Set<String> = [key, targetKey]
        revocationTargets[key] = account
        revocationTargets[targetKey] = account
        defer {
            revocationTargets[key] = nil
            revocationTargets[targetKey] = nil
        }
        revokedRefreshes.formUnion(sessionKeys)
        refreshed = refreshed.filter {
            !sessionKeys.contains($0.key) && !sessionKeys.contains(Self.refreshKey($0.value))
        }
        for pendingKey in sessionKeys { refreshes.removeValue(forKey: pendingKey)?.cancel() }
        for attempt in 0..<2 {
            do {
                try await revokeRequest(account)
                completedRevocations.formUnion(sessionKeys)
                return
            } catch {
                let retryable: Bool
                if case HanlinChatGPTPlanError.server(let code) = error {
                    retryable = (500..<600).contains(code)
                } else if case HanlinChatGPTPlanError.oauth(let status, _, _) = error {
                    retryable = (500..<600).contains(status)
                } else if let network = error as? URLError {
                    retryable = network.code != .cancelled
                } else { retryable = false }
                guard attempt == 0 && retryable else { throw error }
                try await Task<Never, Never>.sleep(for: .seconds(1))
            }
        }
    }

    private func revokeRequest(_ account: HanlinChatGPTPlanCredentials) async throws {
        guard !account.clientID.isEmpty, account.clientID != "dynamic_agent_client",
              !account.refreshToken.isEmpty else {
            throw HanlinChatGPTPlanError.invalidAuthorization
        }
        var discovery = URLRequest(url: URL(string: Self.issuer + "/.well-known/openid-configuration")!)
        discovery.timeoutInterval = 25
        let (bytes, response) = try await session.data(for: discovery)
        guard let http = response as? HTTPURLResponse else {
            throw HanlinChatGPTPlanError.invalidAuthorization
        }
        guard http.statusCode == 200 else { throw Self.serviceError(bytes, response: http) }
        struct Metadata: Decodable {
            let issuer: String
            let revocation_endpoint: URL
        }
        let metadata = try JSONDecoder().decode(Metadata.self, from: bytes)
        let endpoint = metadata.revocation_endpoint
        guard metadata.issuer == Self.issuer,
              endpoint.scheme == "https", endpoint.host == "auth.openai.com",
              endpoint.port == nil || endpoint.port == 443,
              endpoint.user == nil, endpoint.password == nil,
              endpoint.query == nil, endpoint.fragment == nil else {
            throw HanlinChatGPTPlanError.invalidAuthorization
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            .init(name: "token", value: account.refreshToken),
            .init(name: "token_type_hint", value: "refresh_token"),
            .init(name: "client_id", value: account.clientID)
        ]
        request.httpBody = Data((form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        let (data, result) = try await session.data(for: request)
        guard let http = result as? HTTPURLResponse else {
            throw HanlinChatGPTPlanError.invalidAuthorization
        }
        guard http.statusCode == 200 else { throw Self.serviceError(data, response: http) }
    }

    private static func serviceError(_ data: Data, response: HTTPURLResponse) -> HanlinChatGPTPlanError {
        let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let code = value?["error"] as? String ??
            (value?["error"] as? [String: Any])?["code"] as? String
        return .oauth(status: response.statusCode, code: code,
                      requestID: response.value(forHTTPHeaderField: "x-request-id"))
    }

    public func listModels(accessToken:String) async throws -> [HanlinChatGPTPlanModel] {
        var request=URLRequest(url:URL(string:"https://api.openai.com/v1/models")!)
        request.setValue("Bearer "+accessToken,forHTTPHeaderField:"Authorization")
        request.timeoutInterval=25
        let (data,response)=try await session.data(for:request)
        guard let response=response as? HTTPURLResponse else {
            throw HanlinChatGPTPlanError.unavailable
        }
        guard response.statusCode == 200 else {
            throw Self.serviceError(data, response: response)
        }
        struct Catalog: Decodable { let models:[HanlinChatGPTPlanModel] }
        return try JSONDecoder().decode(Catalog.self,from:data).models
            .filter{$0.visibility=="list"}
    }

    private struct Identity: Sendable {let subject:String;let email:String?}
    private static func verifyIdentity(_ jwt:String,clientID:String,
        nonce:String?,accessToken:String, session: URLSession,
        now: @Sendable () -> Date) async throws -> Identity {
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
        let (jwksBytes,jwksResponse)=try await session.data(from:jwksURL)
        guard (jwksResponse as? HTTPURLResponse)?.statusCode==200,
              let keys=try? JSONDecoder().decode(JWKS.self,from:jwksBytes),
              let jwk=keys.keys.first(where:{$0.kid==kid && ($0.alg == nil || $0.alg == alg)}) else {
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
              let exp=payload["exp"] as? TimeInterval,
              exp > now().timeIntervalSince1970-60
        else {throw HanlinChatGPTPlanError.invalidIdentity}
        if let nonce, payload["nonce"] as? String != nonce {
            throw HanlinChatGPTPlanError.invalidIdentity
        }
        let now = now().timeIntervalSince1970
        if let notBefore = payload["nbf"] as? TimeInterval, notBefore > now + 60 {
            throw HanlinChatGPTPlanError.invalidIdentity
        }
        if let issuedAt = payload["iat"] as? TimeInterval, issuedAt > now + 60 {
            throw HanlinChatGPTPlanError.invalidIdentity
        }
        if let authorizedParty = payload["azp"] as? String, authorizedParty != clientID {
            throw HanlinChatGPTPlanError.invalidIdentity
        }
        if let aud=payload["aud"] as? String {
            guard aud==clientID else{throw HanlinChatGPTPlanError.invalidIdentity}
        } else if let aud=payload["aud"] as? [String] {
            guard aud.contains(clientID),
                  aud.count == 1 || payload["azp"] as? String == clientID else {
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

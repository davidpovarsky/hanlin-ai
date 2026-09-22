import Foundation
import UIKit
import Contacts
import MapKit
import LocalAuthentication
import Speech
@preconcurrency import WeatherKit
@preconcurrency import Translation
import CloudKit
import AVFoundation
import Vision
import PDFKit

import HanlinPlatformContracts
import HanlinScriptDeviceServices

public actor HanlinSystemServicesBroker {
    
    public init() {}
    
    // Helper to check capabilities
    nonisolated private func requireCapability(_ cap: String, in context: HanlinHostCallContext) throws {
        guard context.effectiveCapabilities.contains(cap) || context.effectiveCapabilities.contains("all") else {
            throw HanlinHostServiceError.capabilityNotGranted(cap)
        }
    }
    
    // MARK: - 1. Contacts
    
    public func fetchContacts(query: String, context: HanlinHostCallContext) async throws -> [String] {
        try requireCapability("contacts", in: context)
        let store = CNContactStore()
        let authStatus = CNContactStore.authorizationStatus(for: .contacts)
        guard authStatus == .authorized || authStatus == .notDetermined else {
            throw HanlinHostServiceError.systemAuthorizationDenied("contacts")
        }
        
        let granted = try await store.requestAccess(for: .contacts)
        guard granted else {
            throw HanlinHostServiceError.systemAuthorizationDenied("contacts")
        }
        
        let predicate = CNContact.predicateForContacts(matchingName: query)
        let keysToFetch = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
        let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
        return contacts.map { "\($0.givenName) \($0.familyName)" }
    }
    
    // MARK: - 2. Camera/Microphone
    
    public func requestCameraAccess(context: HanlinHostCallContext) async throws -> Bool {
        try requireCapability("camera", in: context)
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: throw HanlinHostServiceError.systemAuthorizationDenied("camera")
        }
    }
    
    public func requestMicrophoneAccess(context: HanlinHostCallContext) async throws -> Bool {
        try requireCapability("microphone", in: context)
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: throw HanlinHostServiceError.systemAuthorizationDenied("microphone")
        }
    }
    
    // MARK: - 3. Speech Recognition
    
    public func recognizeSpeech(audioURL: URL? = nil, context: HanlinHostCallContext) async throws -> String {
        try requireCapability("speech-recognition", in: context)
        let status = SFSpeechRecognizer.authorizationStatus()
        guard status == .authorized || status == .notDetermined else {
            throw HanlinHostServiceError.systemAuthorizationDenied("speech-recognition")
        }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            throw HanlinHostServiceError.systemCapabilityUnavailable("Speech recognizer is not available on this device/simulator.")
        }
        guard let audioURL else {
            throw HanlinHostServiceError.invalidRequest("Audio URL is required for headless speech recognition.")
        }
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result, result.isFinal {
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }
    
    // MARK: - 4. Translation
    
    public func translateText(_ text: String, context: HanlinHostCallContext) async throws -> String {
        try requireCapability("translation", in: context)
        guard #available(iOS 17.4, *) else {
            throw HanlinHostServiceError.systemCapabilityUnavailable("Translation framework requires iOS 17.4+")
        }
        // Apple's Translation framework requires an active SwiftUI TranslationSession (.translationTask).
        // Headless non-interactive execution must explicitly signal session requirement.
        throw HanlinHostServiceError.systemCapabilityUnavailable("Interactive SwiftUI TranslationSession required for Translation framework.")
    }
    
    // MARK: - 5. WeatherKit
    
    public func fetchWeather(latitude: Double, longitude: Double, context: HanlinHostCallContext) async throws -> String {
        try requireCapability("weather", in: context)
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let weatherService = WeatherService.shared
        let weather = try await weatherService.weather(for: location)
        return "Temp: \(weather.currentWeather.temperature.value) C"
    }
    
    // MARK: - 6. Keychain
    
    public func readKeychainItem(account: String, context: HanlinHostCallContext) async throws -> String? {
        try requireCapability("keychain", in: context)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "\(context.appID?.rawValue ?? "agent")_\(account)",
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        guard status == errSecSuccess, let data = dataTypeRef as? Data else {
            if status == errSecItemNotFound {
                return nil
            }
            throw HanlinHostServiceError.invalidRequest("Keychain read failed with status: \(status)")
        }
        
        return String(data: data, encoding: .utf8)
    }
    
    // MARK: - 7. LocalAuthentication
    
    public func authenticateUser(reason: String, context: HanlinHostCallContext) async throws -> Bool {
        try requireCapability("local-authentication", in: context)
        let laContext = LAContext()
        var error: NSError?
        
        guard laContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw HanlinHostServiceError.systemCapabilityUnavailable("Biometrics not available")
        }
        
        return try await laContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
    }
    
    // MARK: - 8. iCloud/CloudKit
    
    public func fetchCloudStatus(context: HanlinHostCallContext) async throws -> CKAccountStatus {
        try requireCapability("cloud", in: context)
        return try await CKContainer.default().accountStatus()
    }
    
    // MARK: - 9. Share Sheet
    
    @MainActor
    public func presentShareSheet(items: [Any], context: HanlinHostCallContext) async throws {
        try requireCapability("share-sheet", in: context)
        guard context.canPresentUI else {
            throw HanlinHostServiceError.invalidCallerContext("Cannot present UI from this context")
        }
        
        guard let windowScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let rootViewController = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            throw HanlinHostServiceError.systemCapabilityUnavailable("No active UI window")
        }
        
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        rootViewController.present(activityVC, animated: true, completion: nil)
    }
    
    // MARK: - 10. MapKit search
    
    public func searchMap(query: String, context: HanlinHostCallContext) async throws -> [MKMapItem] {
        try requireCapability("maps", in: context)
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        let search = MKLocalSearch(request: request)
        let response = try await search.start()
        return response.mapItems
    }
    
    // MARK: - 11. PDF/Vision document utilities
    
    public func recognizeTextInDocument(pdfURL: URL, context: HanlinHostCallContext) async throws -> String {
        try requireCapability("document-utilities", in: context)
        guard let document = PDFDocument(url: pdfURL) else {
            throw HanlinHostServiceError.invalidRequest("Invalid PDF document")
        }
        
        var fullText = ""
        for i in 0..<document.pageCount {
            if let page = document.page(at: i) {
                fullText += page.string ?? ""
            }
        }
        return fullText
    }
    
    // MARK: - 12. Routing to Real Device Services
    
    public func requestCalendarAccess(context: HanlinHostCallContext) async throws -> Bool {
        try requireCapability("calendar", in: context)
        let service = await MainActor.run { HanlinAppleCalendarService() }
        return try await service.requestCalendarAuthorization()
    }
    
    public func requestReminderAccess(context: HanlinHostCallContext) async throws -> Bool {
        try requireCapability("reminders", in: context)
        let service = await MainActor.run { HanlinAppleCalendarService() }
        return try await service.requestReminderAuthorization()
    }
    
    public func requestHealthAccess(context: HanlinHostCallContext) async throws -> Bool {
        try requireCapability("health", in: context)
        guard HanlinAppleHealthService.isHealthDataAvailable else {
            throw HanlinHostServiceError.systemCapabilityUnavailable("HealthKit data is not available on this platform/device.")
        }
        let service = HanlinAppleHealthService()
        try await service.requestReadAuthorization(for: [.steps, .walkingRunningDistance, .activeEnergy, .heartRate])
        return true
    }
    
    public func requestLocationAccess(context: HanlinHostCallContext) async throws -> Bool {
        try requireCapability("location", in: context)
        let manager = await MainActor.run { CLLocationManager() }
        let status = await MainActor.run { manager.authorizationStatus }
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            return true
        case .notDetermined:
            await MainActor.run { manager.requestWhenInUseAuthorization() }
            return true
        default:
            throw HanlinHostServiceError.systemAuthorizationDenied("location")
        }
    }
    
    public func requestNotificationAccess(context: HanlinHostCallContext) async throws -> Bool {
        try requireCapability("notifications", in: context)
        let service = HanlinAppleNotificationService()
        return try await service.requestAuthorization()
    }
}

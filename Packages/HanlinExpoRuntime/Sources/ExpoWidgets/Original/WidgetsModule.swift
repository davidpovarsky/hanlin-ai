import Foundation
import ExpoModulesCore
import ActivityKit
import WidgetKit

let pushNotificationsEnabledKey: String = "ExpoWidgets_EnablePushNotifications"

let onUserInteraction = "onExpoWidgetsUserInteraction"
let onPushToStartTokenReceived = "onExpoWidgetsPushToStartTokenReceived"
let onTokenReceived = "onExpoWidgetsTokenReceived"
let onUserInteractionNotification = Notification.Name(onUserInteraction)

public final class WidgetsModule: Module {
  var pushToStartTokenObserverTask: Task<Void, Never>?

  public func definition() -> ModuleDefinition {
    Name("ExpoWidgets")

    Events(onPushToStartTokenReceived, onTokenReceived, onUserInteraction)

    OnStartObserving(onUserInteraction) {
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleUserInteractionNotification),
        name: onUserInteractionNotification,
        object: nil
      )
    }

    OnStopObserving(onUserInteraction) {
      NotificationCenter.default.removeObserver(
        self,
        name: onUserInteractionNotification,
        object: nil
      )
    }

    OnStartObserving(onPushToStartTokenReceived) {
      if pushNotificationsEnabled {
        observePushToStartToken()
      }
    }

    OnStopObserving(onPushToStartTokenReceived) {
      pushToStartTokenObserverTask?.cancel()
      pushToStartTokenObserverTask = nil
    }

    Constant("widgetsDirectory") { () -> String? in
      guard let appGroupIdentifier = WidgetsStorage.appGroupIdentifier,
            let containerUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
        return nil
      }
      guard let ownerDirectory = HanlinExpoWidgetsIntegration.directoryNamespace(appContext: self.appContext) else { return nil }
      let directoryUrl = containerUrl.appendingPathComponent("ExpoWidgets", isDirectory: true).appendingPathComponent(ownerDirectory, isDirectory: true)
      do {
        try FileManager.default.createDirectory(at: directoryUrl, withIntermediateDirectories: true)
        return directoryUrl.absoluteString
      } catch {
        return nil
      }
    }

    Function("reloadAllWidgets") {
      WidgetCenter.shared.reloadAllTimelines()
    }

    Class("Widget", WidgetObject.self) {
      Constructor { (name: String, layout: String, initialProps: [String: Any]?) in
        let scopedName = try HanlinExpoWidgetsIntegration.qualifiedName(name, kind: "widget", appContext: self.appContext)
        return WidgetObject(name: scopedName, layout: layout, initialProps: initialProps)
      }

      Function("reload") { (widget: WidgetObject) in
        try HanlinExpoWidgetsIntegration.requireActive(name: widget.name, appContext: self.appContext)
        widget.reload()
      }

      Function("updateTimeline") { (widget: WidgetObject, entries: [WidgetsJSTimelineEntry]) in
        try HanlinExpoWidgetsIntegration.requireActive(name: widget.name, appContext: self.appContext)
        try widget.updateTimeline(entries: entries)
      }

      Function("getTimeline") { (widget: WidgetObject) in
        try HanlinExpoWidgetsIntegration.requireActive(name: widget.name, appContext: self.appContext)
        return try widget.getTimeline()
      }

      Function("setConfigurationParameterEnum") { (widget: WidgetObject, parameterName: String, options: [WidgetConfigurationOptionRecord]?) in
        try HanlinExpoWidgetsIntegration.requireActive(name: widget.name, appContext: self.appContext)
        widget.setConfigurationParameterEnum(parameterName: parameterName, options: options)
      }
    }

    Class("LiveActivityFactory", LiveActivityFactory.self) {
      Constructor { (name: String, layout: String) in
        let scopedName = try HanlinExpoWidgetsIntegration.qualifiedName(name, kind: "liveActivity", appContext: self.appContext)
        return LiveActivityFactory(name: scopedName, layout: layout)
      }

      Function("start") { (liveActivity: LiveActivityFactory, props: String?, url: URL?, staleDate: Date?) in
        try HanlinExpoWidgetsIntegration.requireActive(name: liveActivity.name, appContext: self.appContext)
        let instance = try liveActivity.start(props: props, url: url, staleDate: staleDate)
        try HanlinExpoWidgetsIntegration.recordActivity(id: instance.id, name: instance.name, appContext: self.appContext)
        return instance
      }

      Function("getInstances") { (liveActivity: LiveActivityFactory) in
        try HanlinExpoWidgetsIntegration.requireActive(name: liveActivity.name, appContext: self.appContext)
        return try liveActivity.getInstances().filter { HanlinExpoWidgetsIntegration.isActivityCurrent(id: $0.id, name: $0.name, appContext: self.appContext) }
      }
    }

    Class("LiveActivity", LiveActivity.self) {
      Function("getId") { (instance: LiveActivity) in
        try HanlinExpoWidgetsIntegration.requireActive(name: instance.name, appContext: self.appContext)
        return instance.id
      }

      AsyncFunction("update") { (instance: LiveActivity, props: String?, staleDate: Date?) in
        try HanlinExpoWidgetsIntegration.requireActive(name: instance.name, appContext: self.appContext)
        try await instance.update(props: props, staleDate: staleDate)
      }

      AsyncFunction("end") { (instance: LiveActivity, dismissalPolicy: LiveActivityDismissalPolicy?, afterDate: Date?, props: String?, contentDate: Date?) in
        try HanlinExpoWidgetsIntegration.requireActive(name: instance.name, appContext: self.appContext)
        try await instance.end(dismissalPolicy: dismissalPolicy, afterDate: afterDate, props: props, contentDate: contentDate)
      }

      AsyncFunction("getPushToken") { (instance: LiveActivity) in
        try HanlinExpoWidgetsIntegration.requireActive(name: instance.name, appContext: self.appContext)
        return try instance.getPushToken()
      }
    }
  }

  @objc func handleUserInteractionNotification(_ notification: Notification) {
    guard let userInfo = notification.userInfo as? [String: Any],
          let eventData = userInfo["eventData"] as? [String: Any]
    else { return }
    guard let ownedEvent = HanlinExpoWidgetsIntegration.eventData(eventData, appContext: appContext) else { return }
    self.sendEvent(onUserInteraction, ownedEvent)
  }

  private func sendPushToStartToken(activityPushToStartToken: String) {
    sendEvent(
      onPushToStartTokenReceived,
      [
        "activityPushToStartToken": activityPushToStartToken
      ]
    )
  }

  private func observePushToStartToken() {
    guard #available(iOS 17.2, *), ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    pushToStartTokenObserverTask = Task {
      let initialToken = (Activity<LiveActivityAttributes>.pushToStartToken?.reduce("") { $0 + String(format: "%02x", $1) })
      if let initialToken {
        sendPushToStartToken(activityPushToStartToken: initialToken)
      }

      for await data in Activity<LiveActivityAttributes>.pushToStartTokenUpdates {
        let token = data.reduce("") { $0 + String(format: "%02x", $1) }
        if token != initialToken {
          sendPushToStartToken(activityPushToStartToken: token)
        }
      }
    }
  }

  private var pushNotificationsEnabled: Bool {
    Bundle.main.object(forInfoDictionaryKey: pushNotificationsEnabledKey) as? Bool ?? false
  }
}

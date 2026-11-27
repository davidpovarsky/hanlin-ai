//
//  ScriptWidgetRuntimePromise.swift
//  ScriptWidget
//
//  Created by everettjf on 2020/12/10.
//

import Foundation
import JavaScriptCore

@objc protocol ScriptWidgetRuntimePromiseExports: JSExport {
    func then(_ resolve: JSValue, _ reject: JSValue) -> Void
}

class ScriptWidgetRuntimePromise: NSObject, ScriptWidgetRuntimePromiseExports {

    var callback: (JSValue,JSValue) -> Void
    private let state: ScriptWidgetRunningState?

    init(callback: @escaping (JSValue,JSValue) -> Void) {
        self.callback = callback
        self.state = JSContext.current()?.scriptWidgetRunningState
    }

    func then(_ resolve: JSValue, _ reject: JSValue) -> Void {
        guard let state = state ?? resolve.context?.scriptWidgetRunningState else { self.callback(resolve, reject); return }
        guard state.isCurrentExecution else {
            reject.call(withArguments: ["[execution_inactive] The widget execution is no longer current"])
            return
        }
        let delivery = ScriptWidgetPromiseDelivery(state: state, resolve: resolve, reject: reject)
        let success: @convention(block) (JSValue) -> Void = { delivery.finish($0, rejected: false) }
        let failure: @convention(block) (JSValue) -> Void = { delivery.finish($0, rejected: true) }
        guard let guardedResolve = JSValue(object: success, in: resolve.context),
              let guardedReject = JSValue(object: failure, in: reject.context) else {
            delivery.cancel()
            reject.call(withArguments: ["[execution_unavailable] Promise delivery could not be installed"])
            return
        }
        self.callback(guardedResolve, guardedReject)
    }
}

/// At most one callback can cross back into JS. Native payloads from a finished
/// or replaced execution are discarded before invoking user continuations.
final class ScriptWidgetPromiseDelivery: NSObject {
    private struct Callbacks {
        let resolve: JSValue
        let reject: JSValue
    }
    private let state: ScriptWidgetRunningState
    private var callbacks: Callbacks?
    private let lock = NSLock()
    private var settled = false

    init(state: ScriptWidgetRunningState, resolve: JSValue, reject: JSValue) {
        self.state = state
        self.callbacks = Callbacks(resolve: resolve, reject: reject)
        super.init()
        // Native retention of the guarded blocks is not a JS-reachable managed
        // ownership graph. Keep pending continuations until settlement or
        // cancellation; the weak session entry can break this temporary VM
        // cycle even while delivery is waiting on the callback queue.
        if !state.executionSession.registerPromiseDelivery(self) { cancel() }
    }

    deinit {
        state.executionSession.completePromiseDelivery(self)
    }

    func finish(_ value: JSValue, rejected: Bool) {
        state.executionSession.callbackQueue.async { self.deliver(value, rejected: rejected) }
    }

    func cancel() {
        // Release JSValues outside both locks: their final release may dispose
        // of the VM and its native callback blocks.
        let callbacks = takeCallbacks()
        withExtendedLifetime(callbacks) {}
    }

    private func takeCallbacks() -> Callbacks? {
        lock.lock()
        guard !settled else { lock.unlock(); return nil }
        settled = true
        let callbacks = self.callbacks
        self.callbacks = nil
        lock.unlock()
        state.executionSession.completePromiseDelivery(self)
        return callbacks
    }

    private func deliver(_ value: JSValue, rejected: Bool) {
        guard let callbacks = takeCallbacks() else { return }
        guard state.executionSession.isActive else { return }
        guard state.isCurrentExecution else {
            callbacks.reject.call(withArguments: ["[execution_identity_changed] Reload the widget before continuing"])
            return
        }
        (rejected ? callbacks.reject : callbacks.resolve).call(withArguments: [value])
    }
}

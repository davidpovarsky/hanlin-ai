import { Application, NativeWindowEvents } from '@nativescript/core';
import { IOSNativeWindow } from '@nativescript/core/native-window/native-window.ios';
import { IOSHelper } from '@nativescript/core/ui/core/view/view-helper';
import { createHostServicesForBridge } from '@hanlin/host-services';

// This adapter deliberately uses the shipped 9.1 IOSNativeWindow lifecycle.
// Only embedded presentation is replaced: the Host still owns every UIWindow.
class HanlinEmbeddedWindow extends IOSNativeWindow {
  constructor(context) {
    super(undefined, undefined, context.windowID, !Application.primaryWindow, 'embedded');
    this.context = context;
  }

  _setNativeContent(view) {
    const controller = this._getViewController(view);
    this._setViewControllerView(view);
    this.context.presentViewController(controller);
    view.on(IOSHelper.traitCollectionColorAppearanceChangedEvent, () => {
      this._setSystemAppearance(this._getSystemAppearanceValue(controller.traitCollection.userInterfaceStyle));
    });
    view.on(IOSHelper.traitCollectionLayoutDirectionChangedEvent, () => {
      this._setLayoutDirection(this._getLayoutDirectionValue(controller.traitCollection.layoutDirection));
    });
  }

  _getSystemAppearance() {
    const traits = this.context?.containerController?.traitCollection;
    return traits ? this._getSystemAppearanceValue(traits.userInterfaceStyle) : null;
  }

  _getLayoutDirection() {
    const traits = this.context?.containerController?.traitCollection;
    return traits ? this._getLayoutDirectionValue(traits.layoutDirection) : null;
  }
}

/**
 * Register once while the declared package entry loads. Each call receives a
 * newly bound provider and must produce its own root. Module-wide caches may
 * still be shared deliberately; request state belongs in this callback.
 */
export function registerWindowFactory(factory) {
  if (typeof HanlinNativeScriptWindowFactoryRegistry === 'undefined') {
    throw new Error('Hanlin NativeScript window metadata is unavailable.');
  }
  const app = Application.ios;
  const accepted = HanlinNativeScriptWindowFactoryRegistry.registerFactory(context => {
    const window = new HanlinEmbeddedWindow(context);
    const services = createHostServicesForBridge(context.servicesBridge);
    let closed = false;
    app._registerWindow(window);
    window._notifyEvent(NativeWindowEvents.attached);
    context.setLifecycleHandler((event, surface) => {
      if (closed) return;
      if (event === 'close') {
        closed = true;
        window._notifyEvent(NativeWindowEvents.close);
        app._unregisterWindow(window);
        return;
      }
      if (event === 'detached') {
        if (window.state !== 'detached') window._detach();
        return;
      }
      if (surface) {
        const wasDetached = window.state === 'detached';
        window._reattach(surface.windowScene ?? undefined, surface);
        if (wasDetached && window.rootView) window.setContent(window.rootView);
        window.orientation();
        window.systemAppearance();
        window.layoutDirection();
      }
      if (event !== 'surface' && event !== 'attached') window._notifyEvent(event);
    });
    const install = root => {
      if (closed || context.closed) return;
      if (root == null) return; // The factory may supply content through window.setContent later.
      if (root._nativeWindow && root._nativeWindow !== window && root._nativeWindow.state !== 'closed') {
        throw new Error('A window factory must return a fresh root for each invocation.');
      }
      window.setContent(root);
    };
    const failure = error => {
      if (closed || context.closed) return;
      const message = String(error?.message ?? error);
      context.showFailure(message);
      void services.miniapps.complete({status: 'error', message}).catch(() => {});
    };
    try {
      const content = factory(Object.freeze({id: context.windowID, window, services}));
      if (content && typeof content.then === 'function') content.then(install).catch(failure);
      else install(content);
    } catch (error) {
      // Native open catches this and invalidates only the new context.
      throw error;
    }
  });
  if (!accepted) throw new Error('The active package already owns a window factory or is not in factory mode.');
  app.notifyReady();
  app._ensureAppCssLoaded();
}

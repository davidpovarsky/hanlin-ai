"""Exact shipping targets shared by generation and signing.

The original ten role/bundle/environment/entitlement tuples are stable.
Keyboard, notification content and locked capture ship only with MiniApps.
"""
from dataclasses import dataclass


@dataclass(frozen=True)
class ExtensionSpec:
    key: str
    ai_target: str | None
    mini_target: str
    mini_folder: str
    suffix: str
    sdk_product: str

    @property
    def template_target(self):
        if self.ai_target is not None:
            return self.ai_target
        return ("ChavrusaChatTranslationProvider" if self.key == "camera-capture"
                else "ChavrusaChatNotificationService")


EXTENSIONS = (
    ExtensionSpec("widgets", "HanlinScriptingWidgets", "HanlinMiniAppsWidgets", "Widgets", "widgets", "HanlinWidgetUI"),
    ExtensionSpec("share", "ChavrusaChatShare", "HanlinMiniAppsShare", "Share", "share", "HanlinShareExtensionUI"),
    ExtensionSpec("translation", "ChavrusaChatTranslationProvider", "HanlinMiniAppsTranslationProvider", "Translation", "translation-provider", "HanlinTranslationUI"),
    ExtensionSpec("notification", "ChavrusaChatNotificationService", "HanlinMiniAppsNotificationService", "Notification", "notification-service", "HanlinNotificationExtension"),
    ExtensionSpec("keyboard", None, "HanlinMiniAppsKeyboard", "Keyboard", "keyboard", "HanlinKeyboardUI"),
    ExtensionSpec("notification-content", None, "HanlinMiniAppsNotificationContent", "NotificationContent", "notification-content", "HanlinNotificationContentUI"),
    ExtensionSpec("camera-capture", None, "HanlinMiniAppsCameraCapture", "CameraCapture", "camera-capture", "HanlinCameraCaptureUI"),
)
NEW_EXTENSION_KEYS = frozenset({"keyboard", "notification-content", "camera-capture"})
MINIAPPS_EXTENSIONS = tuple((s.mini_target, s.template_target, s.mini_folder, s.suffix) for s in EXTENSIONS)
APP_BUNDLES = {"ai": "com.itorah.chavrusachat", "miniapps": "com.itorah.hanlinminiapps"}


@dataclass(frozen=True)
class SigningTarget:
    role: str
    owner: str
    target: str
    bundle: str
    profile_environment: str
    entitlements: str


def _extension_signing(spec, owner):
    if owner not in APP_BUNDLES or (owner == "ai" and spec.ai_target is None):
        raise ValueError("Extension is not owned by the requested shipping app")
    mini = owner == "miniapps"
    target = spec.mini_target if mini else spec.ai_target
    folder = "HanlinMiniAppsExtensions/" + spec.mini_folder if mini else spec.ai_target
    # These underscore roles and suffix-derived environment names are already
    # consumed by the existing MiniApps profile map and release workflow.
    role = "miniapps_" + spec.suffix.replace("-", "_") if mini else spec.key
    suffix = (spec.suffix.replace("-", "_").upper() if mini
              else "NOTIFICATION_SERVICE" if spec.key == "notification" else spec.key.upper())
    environment = "APPLE_" + ("MINIAPPS_" if mini else "") + suffix + "_PROVISIONING_PROFILE_B64"
    return SigningTarget(role, owner, target, APP_BUNDLES[owner] + "." + spec.suffix,
                         environment, folder + "/" + target + ".entitlements")


_specs = {spec.key: spec for spec in EXTENSIONS}
SIGNING_TARGETS = (
    SigningTarget("ai", "ai", "HanlinApp", APP_BUNDLES["ai"], "APPLE_MAIN_PROVISIONING_PROFILE_B64", "AI_HLY/AI_HLY.entitlements"),
    SigningTarget("miniapps", "miniapps", "HanlinMiniApps", APP_BUNDLES["miniapps"], "APPLE_MINIAPPS_PROVISIONING_PROFILE_B64", "HanlinMiniAppsApp/HanlinMiniApps.entitlements"),
    *(_extension_signing(_specs[key], "ai") for key in ("share", "widgets", "translation", "notification")),
    *(_extension_signing(spec, "miniapps") for spec in EXTENSIONS),
)
ROLES = [(s.role, s.bundle, s.profile_environment, s.entitlements) for s in SIGNING_TARGETS]


def signing_targets_for_owner(owner):
    if owner not in APP_BUNDLES:
        raise ValueError("Unknown shipping app owner: " + owner)
    return tuple(target for target in SIGNING_TARGETS if target.owner == owner)


def embedded_product_bundles(application):
    """Both native extension containers are part of one exported app."""
    return [application, *sorted(application.glob("PlugIns/*.appex")),
            *sorted(application.glob("Extensions/*.appex"))]

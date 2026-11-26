"""Exact shipping targets shared by project generation and signing tools.

Keep the two app roles first and retain the established six role/environment
names. Each extension belongs to one app; ExtensionKit is still an extension,
not an additional app or an entitlement-sharing shortcut.
"""
from dataclasses import dataclass


@dataclass(frozen=True)
class ExtensionSpec:
    key: str
    ai_target: str
    mini_target: str
    mini_folder: str
    suffix: str
    sdk_product: str


EXTENSIONS = (
    ExtensionSpec("widgets", "HanlinScriptingWidgets", "HanlinMiniAppsWidgets", "Widgets", "widgets", "HanlinWidgetUI"),
    ExtensionSpec("share", "ChavrusaChatShare", "HanlinMiniAppsShare", "Share", "share", "HanlinShareExtensionUI"),
    ExtensionSpec("translation", "ChavrusaChatTranslationProvider", "HanlinMiniAppsTranslationProvider", "Translation", "translation-provider", "HanlinTranslationUI"),
    ExtensionSpec("notification", "ChavrusaChatNotificationService", "HanlinMiniAppsNotificationService", "Notification", "notification-service", "HanlinNotificationExtension"),
    ExtensionSpec("keyboard", "ChavrusaChatKeyboard", "HanlinMiniAppsKeyboard", "Keyboard", "keyboard", "HanlinKeyboardUI"),
    ExtensionSpec("notification-content", "ChavrusaChatNotificationContent", "HanlinMiniAppsNotificationContent", "NotificationContent", "notification-content", "HanlinNotificationContentUI"),
    ExtensionSpec("camera-capture", "ChavrusaChatCameraCapture", "HanlinMiniAppsCameraCapture", "CameraCapture", "camera-capture", "HanlinCameraCaptureUI"),
)
NEW_EXTENSION_KEYS = frozenset({"keyboard", "notification-content", "camera-capture"})
MINIAPPS_EXTENSIONS = tuple((s.mini_target, s.ai_target, s.mini_folder, s.suffix) for s in EXTENSIONS)
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
    mini = owner == "miniapps"
    target = spec.mini_target if mini else spec.ai_target
    folder = "HanlinMiniAppsExtensions/" + spec.mini_folder if mini else spec.ai_target
    role = ("miniapps-" if mini else "") + spec.key
    # Keep the original notification-service environment name.
    suffix = "NOTIFICATION_SERVICE" if spec.key == "notification" else spec.key.upper().replace("-", "_")
    environment = "APPLE_" + ("MINIAPPS_" if mini else "") + suffix + "_PROVISIONING_PROFILE_B64"
    return SigningTarget(role, owner, target, APP_BUNDLES[owner] + "." + spec.suffix,
                         environment, folder + "/" + target + ".entitlements")


_specs = {spec.key: spec for spec in EXTENSIONS}
SIGNING_TARGETS = (
    SigningTarget("ai", "ai", "HanlinApp", APP_BUNDLES["ai"], "APPLE_MAIN_PROVISIONING_PROFILE_B64", "AI_HLY/AI_HLY.entitlements"),
    SigningTarget("miniapps", "miniapps", "HanlinMiniApps", APP_BUNDLES["miniapps"], "APPLE_MINIAPPS_PROVISIONING_PROFILE_B64", "HanlinMiniAppsApp/HanlinMiniApps.entitlements"),
    *(_extension_signing(_specs[key], "ai") for key in ("share", "widgets", "translation", "notification")),
    *(_extension_signing(spec, "miniapps") for spec in EXTENSIONS if spec.key not in NEW_EXTENSION_KEYS),
    *(_extension_signing(spec, owner) for owner in ("ai", "miniapps") for spec in EXTENSIONS if spec.key in NEW_EXTENSION_KEYS),
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

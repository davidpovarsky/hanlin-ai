# Explicit remaining legacy UI decisions — 2026-11-18

Source implementation; native acceptance pending.

MODEL-03: the unused scroll/menu preference no longer appears in General Settings. The original stored UserInfo.modelSelectorStyle field and values remain intact. Repository consumers already use the single searchable assistant picker. MODEL-04 no longer has a top-seven source branch.

RESULT-05: removed both three-line rolling activity/reasoning previews. The existing activity header and its concise timeline summary remain; the original user-controlled disclosure retains reasoning, tool results, failure and cancellation states. No transcript content is deleted.

SYS-06/07: the old domain-specific study shortcut is now presented as a general user-scheduled alarm. Its stable intent type, parameters, permission request and AlarmKit scheduling remain, preserving existing Shortcuts references. The actual alarm now uses the title entered by the user instead of a hard-coded old brand. Notifications use Hanlin labels. The existing notification category and app identity are retained.

SYS-08: the stable Vision intent and URL still reach the current contextual camera sheet. Its visible title/description now name Hanlin Camera. The removed standalone Vision tab remains removed.

Alarm usage descriptions in the existing two Info.plist files now describe the generic product. No unrelated plist value changed. New intent labels/descriptions have English, Hebrew and Simplified Chinese catalogue values. The OS Siri/Shortcuts/AlarmKit and physical-camera gates remain NOT_RUN; these changes are not proof of OS delivery or every spoken language.

INPUT-17 and RUN-11 source review: Observe & Continue is already contextual in the original Composer, and the capability-gated Voice Generation switch binds directly to ifAudio. Those paths are preserved, with native behavior acceptance still required.

Apple API references: https://developer.apple.com/documentation/alarmkit/alarmpresentation/alert-swift.struct and https://developer.apple.com/documentation/AlarmKit/scheduling-an-alarm-with-alarmkit.

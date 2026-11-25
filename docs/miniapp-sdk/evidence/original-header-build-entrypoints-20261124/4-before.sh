set -euxo pipefail
rm -rf "$LOG_DIR/SimulatorWarmBuildResult.xcresult"
has_tests=false
if [ -n "$SIMULATOR_BUILD_FOR_TESTING_ARGS" ] || [ "$RUN_FULL_VALIDATION" = "true" ] || [ "$RUN_SIMULATOR_UNIT" = "true" ] || [ "$RUN_SIMULATOR_SCRIPTING_ACCEPTANCE" = "true" ] || [ "$RUN_SIMULATOR_TARGETED_UI" = "true" ]; then
  has_tests=true
fi
build_actions=(build)
testing_scope_flags=()
testing_build_settings=()
if [ "$has_tests" = "true" ] && [ "${{ inputs.nativescript_poc_only }}" != "true" ]; then
  build_actions=(build-for-testing)
  testing_build_settings=('SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) HANLIN_TESTING')
  if [ -n "$SIMULATOR_BUILD_FOR_TESTING_ARGS" ]; then
    skip_next=false
    for arg in $SIMULATOR_BUILD_FOR_TESTING_ARGS; do
      if [ "$skip_next" = "true" ]; then
        skip_next=false
        continue
      fi
      if [ "$arg" = "-configuration" ]; then
        skip_next=true
        continue
      fi
      testing_scope_flags+=("$arg")
    done
  fi
fi
started_at="$(date +%s)"
repo_root="$PWD"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME_NAME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -clonedSourcePackagesDirPath "$CLONED_PACKAGES_PATH" \
  -resultBundlePath "$LOG_DIR/SimulatorWarmBuildResult.xcresult" \
  -showBuildTimingSummary \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  SWIFT_ENABLE_EXPLICIT_MODULES=NO \
  CLANG_CXX_LANGUAGE_STANDARD=gnu++20 \
  FRAMEWORK_SEARCH_PATHS="$repo_root/Packages/HanlinExpoRuntime/Artifacts/ModularFrameworks $repo_root/Artifacts/ModularFrameworks \$(SRCROOT)/Packages/HanlinExpoRuntime/Artifacts/ModularFrameworks \$(SRCROOT)/Artifacts/ModularFrameworks \$(inherited)" \
  HEADER_SEARCH_PATHS="$repo_root/Packages/HanlinExpoRuntime/Artifacts/ReactModularHeaders $repo_root/Artifacts/ReactModularHeaders $repo_root/Packages/HanlinExpoRuntime/Artifacts/ReactNativeDependencies.xcframework/Headers $repo_root/Artifacts/ReactNativeDependencies.xcframework/Headers $repo_root/Packages/HanlinExpoRuntime/Artifacts/ModularFrameworks/react.framework/Headers $repo_root/Packages/HanlinExpoRuntime/Artifacts/ModularFrameworks/react.framework/Headers/react \$(SRCROOT)/Packages/HanlinExpoRuntime/Artifacts/ReactModularHeaders \$(SRCROOT)/Artifacts/ReactModularHeaders \$(inherited) \$(BUILT_PRODUCTS_DIR)/React.framework/Headers \$(BUILT_PRODUCTS_DIR)/react.framework/Headers \$(BUILT_PRODUCTS_DIR)/ExpoModulesCore.framework/Headers \$(BUILT_PRODUCTS_DIR)/Python.framework/Headers" \
  CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES=YES \
  CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER=NO \
  WARNING_CFLAGS='$(inherited) -Wno-quoted-include-in-framework-header -Wno-non-modular-include-in-framework-module' \
  OTHER_CFLAGS='$(inherited) -Wno-quoted-include-in-framework-header -Wno-non-modular-include-in-framework-module' \
  OTHER_SWIFT_FLAGS="-Xcc -F$repo_root/Packages/HanlinExpoRuntime/Artifacts/ModularFrameworks -Xcc -F$repo_root/Artifacts/ModularFrameworks -Xcc -I$repo_root/Packages/HanlinExpoRuntime/Artifacts/ReactModularHeaders -Xcc -I$repo_root/Artifacts/ReactModularHeaders -Xcc -I$repo_root/Packages/HanlinExpoRuntime/Artifacts/ReactNativeDependencies.xcframework/Headers -Xcc -I$repo_root/Artifacts/ReactNativeDependencies.xcframework/Headers -Xcc -I$repo_root/Packages/HanlinExpoRuntime/Artifacts/ModularFrameworks/react.framework/Headers -Xcc -I$repo_root/Packages/HanlinExpoRuntime/Artifacts/ModularFrameworks/react.framework/Headers/react -Xcc -F\$(SRCROOT)/Packages/HanlinExpoRuntime/Artifacts/ModularFrameworks -Xcc -F\$(SRCROOT)/Artifacts/ModularFrameworks \$(inherited) -Xcc -Wno-quoted-include-in-framework-header -Xcc -Wno-non-modular-include-in-framework-module -Xcc -I\$(BUILT_PRODUCTS_DIR)/React.framework/Headers -Xcc -I\$(BUILT_PRODUCTS_DIR)/react.framework/Headers -Xcc -I\$(BUILT_PRODUCTS_DIR)/React.framework/Headers/react -Xcc -I\$(BUILT_PRODUCTS_DIR)/ExpoModulesCore.framework/Headers" \
  ENABLE_TESTABILITY=YES \
  IPHONEOS_DEPLOYMENT_TARGET="$IOS_DEPLOYMENT_TARGET" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  "${testing_build_settings[@]+"${testing_build_settings[@]}"}" \
  "${testing_scope_flags[@]+"${testing_scope_flags[@]}"}" \
  "${build_actions[@]}" \
  2>&1 | tee "$LOG_DIR/06-warm-rebuild.log"
duration_seconds="$(( $(date +%s) - started_at ))"
echo "$duration_seconds" > "$LOG_DIR/06-warm-rebuild-duration-seconds.txt"
echo "Same-run simulator no-op rebuild duration: ${duration_seconds}s"

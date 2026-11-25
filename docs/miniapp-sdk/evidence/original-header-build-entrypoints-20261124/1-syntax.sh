set -euxo pipefail

{
  echo "Starting unsigned iOS build..."
  echo "Project: $PROJECT_PATH"
  echo "Scheme: $SCHEME_NAME"
  echo "App name: $APP_NAME"
  echo "Configuration: $CONFIGURATION"
  echo "Deployment target override: iOS $IOS_DEPLOYMENT_TARGET"
  echo "DerivedData: $DERIVED_DATA_PATH"
  echo "Packages: $CLONED_PACKAGES_PATH"
  echo

  rm -rf "$LOG_DIR/BuildResult.xcresult"
  build_actions=(build)
  if [ "GITHUB_EXPRESSION" = "true" ]; then
    build_actions=(clean build)
  fi
  repo_root="$PWD"
  started_at="$(date +%s)"

  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME_NAME" \
    -configuration "$CONFIGURATION" \
    -destination "generic/platform=iOS" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -clonedSourcePackagesDirPath "$CLONED_PACKAGES_PATH" \
    -resultBundlePath "$LOG_DIR/BuildResult.xcresult" \
    -showBuildTimingSummary \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    FRAMEWORK_SEARCH_PATHS="$repo_root/Packages/HanlinExpoRuntime/Artifacts/ModularFrameworks $repo_root/Artifacts/ModularFrameworks \$(SRCROOT)/Packages/HanlinExpoRuntime/Artifacts/ModularFrameworks \$(SRCROOT)/Artifacts/ModularFrameworks \$(inherited)" \
    HEADER_SEARCH_PATHS="$repo_root/Packages/HanlinExpoRuntime/Artifacts/ReactModularHeaders $repo_root/Artifacts/ReactModularHeaders $repo_root/Packages/HanlinExpoRuntime/Artifacts/ModularFrameworks/react.framework/Headers $repo_root/Packages/HanlinExpoRuntime/Artifacts/ModularFrameworks/react.framework/Headers/react \$(SRCROOT)/Packages/HanlinExpoRuntime/Artifacts/ReactModularHeaders \$(SRCROOT)/Artifacts/ReactModularHeaders \$(inherited) \$(BUILT_PRODUCTS_DIR)/React.framework/Headers \$(BUILT_PRODUCTS_DIR)/ExpoModulesCore.framework/Headers \$(BUILT_PRODUCTS_DIR)/Python.framework/Headers" \
    CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES=YES \
    CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER=NO \
    WARNING_CFLAGS='$(inherited) -Wno-quoted-include-in-framework-header -Wno-non-modular-include-in-framework-module' \
    OTHER_CFLAGS='$(inherited) -Wno-quoted-include-in-framework-header -Wno-non-modular-include-in-framework-module' \
    OTHER_SWIFT_FLAGS="-Xcc -F$repo_root/Packages/HanlinExpoRuntime/Artifacts/ModularFrameworks -Xcc -F$repo_root/Artifacts/ModularFrameworks -Xcc -I$repo_root/Packages/HanlinExpoRuntime/Artifacts/ReactModularHeaders -Xcc -I$repo_root/Artifacts/ReactModularHeaders -Xcc -I$repo_root/Packages/HanlinExpoRuntime/Artifacts/ModularFrameworks/react.framework/Headers -Xcc -I$repo_root/Packages/HanlinExpoRuntime/Artifacts/ModularFrameworks/react.framework/Headers/react -Xcc -F\$(SRCROOT)/Packages/HanlinExpoRuntime/Artifacts/ModularFrameworks -Xcc -F\$(SRCROOT)/Artifacts/ModularFrameworks \$(inherited) -Xcc -Wno-quoted-include-in-framework-header -Xcc -Wno-non-modular-include-in-framework-module -Xcc -I\$(BUILT_PRODUCTS_DIR)/React.framework/Headers -Xcc -I\$(BUILT_PRODUCTS_DIR)/React.framework/Headers/react -Xcc -I\$(BUILT_PRODUCTS_DIR)/ExpoModulesCore.framework/Headers" \
    IPHONEOS_DEPLOYMENT_TARGET="$IOS_DEPLOYMENT_TARGET" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    PROVISIONING_PROFILE_SPECIFIER="" \
    DEVELOPMENT_TEAM="" \
    "${build_actions[@]}" 2>&1 | tee "$LOG_DIR/07-xcodebuild.raw.log"

  duration_seconds="$(( $(date +%s) - started_at ))"
  echo "$duration_seconds" > "$LOG_DIR/07-app-compilation-duration-seconds.txt"
  echo "Application compilation duration: ${duration_seconds}s"

  echo
  echo "Build command completed."
} 2>&1 | tee "$LOG_DIR/07-build-step-wrapper.log"

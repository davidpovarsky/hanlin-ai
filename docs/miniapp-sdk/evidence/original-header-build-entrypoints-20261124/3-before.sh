set -euxo pipefail
rm -rf "$LOG_DIR/SimulatorBuildResult.xcresult"
poc_build_settings=()
if [ "${{ inputs.nativescript_poc_only }}" = "true" ]; then
  poc_build_settings=('OTHER_SWIFT_FLAGS=$(inherited) -DHANLIN_NATIVESCRIPT_POC')
fi

# Determine whether this run executes tests (requires build-for-testing) or only app launch
has_tests=false
if [ -n "$SIMULATOR_BUILD_FOR_TESTING_ARGS" ] || [ "$RUN_FULL_VALIDATION" = "true" ] || [ "$RUN_SIMULATOR_UNIT" = "true" ] || [ "$RUN_SIMULATOR_SCRIPTING_ACCEPTANCE" = "true" ] || [ "$RUN_SIMULATOR_TARGETED_UI" = "true" ]; then
  has_tests=true
fi

build_actions=(build)
testing_build_settings=()
if [ "$has_tests" = "true" ] && [ "${{ inputs.nativescript_poc_only }}" != "true" ]; then
  build_actions=(build-for-testing)
  # Release runtime tests retain the same read-only probes as Debug.
  # Do not enable DEBUG behavior in the production NativeScript host.
  testing_build_settings=('SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) HANLIN_TESTING')
fi
if [ "${{ inputs.force_clean_build }}" = "true" ]; then
  build_actions=(clean "${build_actions[@]}")
fi

testing_scope_flags=()
if [ "$has_tests" = "true" ] && [ "${{ inputs.nativescript_poc_only }}" != "true" ]; then
  if [ -n "$SIMULATOR_BUILD_FOR_TESTING_ARGS" ]; then
    # shellcheck disable=SC2086
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
  elif [ "$RUN_FULL_VALIDATION" = "true" ]; then
    testing_scope_flags+=("-only-testing:AI_HLYTests" "-only-testing:AI_HLYUITests")
  else
    if [ "$RUN_SIMULATOR_UNIT" = "true" ]; then
      testing_scope_flags+=("-only-testing:${SIMULATOR_UNIT_FILTER:-AI_HLYTests}")
    fi
    if [ "$RUN_SIMULATOR_SCRIPTING_ACCEPTANCE" = "true" ]; then
      testing_scope_flags+=("-only-testing:AI_HLYTests/HanlinScriptingAcceptanceTests")
    fi
    if [ "$RUN_SIMULATOR_TARGETED_UI" = "true" ]; then
      testing_scope_flags+=("-only-testing:${SIMULATOR_UI_FILTER:-AI_HLYUITests}")
    fi
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
  -resultBundlePath "$LOG_DIR/SimulatorBuildResult.xcresult" \
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
  "${poc_build_settings[@]+"${poc_build_settings[@]}"}" \
  "${testing_build_settings[@]+"${testing_build_settings[@]}"}" \
  "${testing_scope_flags[@]+"${testing_scope_flags[@]}"}" \
  "${build_actions[@]}" 2>&1 | tee "$LOG_DIR/06-xcodebuild-simulator.log"
echo "$(( $(date +%s) - started_at ))" > "$LOG_DIR/06-app-compilation-duration-seconds.txt"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/${CONFIGURATION}-iphonesimulator/AI_Hanlin.app"
test -d "$APP_PATH"
rm -rf build/SimulatorRuntimeApp
mkdir -p build/SimulatorRuntimeApp
ditto "$APP_PATH" build/SimulatorRuntimeApp/AI_Hanlin.app
# A restored DerivedData cache can leave the downstream test bundle in
# the product app. Keep the runtime copy representative of the shipped
# application before validating its dyld closure and launching it.
rm -rf build/SimulatorRuntimeApp/AI_Hanlin.app/PlugIns/AI_HLYTests.xctest
rm -rf build/SimulatorRuntimeApp/AI_Hanlin.app/PlugIns/AI_HLYUITests.xctest
rm -rf build/SimulatorRuntimeApp/AI_Hanlin.app/Frameworks/XC*
rm -rf build/SimulatorRuntimeApp/AI_Hanlin.app/Frameworks/libXCTest*
rm -rf build/SimulatorRuntimeApp/AI_Hanlin.app/Frameworks/Testing.framework
rm -rf build/SimulatorRuntimeApp/AI_Hanlin.app/Frameworks/lib_Testing*
test ! -e build/SimulatorRuntimeApp/AI_Hanlin.app/PlugIns/AI_HLYTests.xctest
# Removing sealed test resources invalidates the copied app's signature.
# Re-seal only this simulator copy, retaining its Xcode entitlements.
codesign --force --sign - --timestamp=none \
  --preserve-metadata=identifier,entitlements,flags --generate-entitlement-der \
  build/SimulatorRuntimeApp/AI_Hanlin.app \
  > "$LOG_DIR/07-simulator-runtime-signature.log" 2>&1
codesign --verify --deep --strict --verbose=2 build/SimulatorRuntimeApp/AI_Hanlin.app \
  >> "$LOG_DIR/07-simulator-runtime-signature.log" 2>&1

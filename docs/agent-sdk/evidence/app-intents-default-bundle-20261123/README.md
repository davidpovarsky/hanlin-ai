# AppIntents default bundle continuation

Run 45224582718 recompiled both original SDK source files but rejected nine metadata resources with explicit bundle: .main. The original compiler excerpt and full log identity are retained here. No selected application test executed.

The correction keeps all 20 metadata keys, the generated executable table, three locales, original intent types, and runtime dialog bundle. It uses the documented default-main initializer form, avoiding the competing explicit Bundle overload. Native acceptance remains required. The next existing application build also retains original Swift constant metadata for a precise diagnosis if extraction fails again; it does not disable extraction or suppress errors.

The existing FoundationModels inspector is explicitly opted into its bounded macOS runner availability-only query during this necessary continuation. This does not run a model or tools and is not iOS device acceptance.

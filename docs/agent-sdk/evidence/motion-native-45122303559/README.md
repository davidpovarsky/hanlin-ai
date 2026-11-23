# Motion native gate 45122303559

The actual canonical SDK fixture reached an owned, ready iPad simulator and resolved its selected dependencies on Xcode27.2 / Swift6.4.2. Xcode then rejected the existing EquatableMacros dependency at `ComputeTargetDependencyGraph` because the standalone Motion command omitted the original project's headless macro admission option. **No Swift UI source or XCTest case executed.** This is not an animation test failure.

The verified source is `65fdc2ed9cd1ed563b86d98cee2dab7f665f714c`. The artifact API digest matches the downloaded ZIP. The committed fixture inputs matched that source; all363 canonical source/resource entries and the selected manifest were recorded. Dependency checkout bytes and final packaged resources were not recorded because their gate runs after build.

The repair is limited to the existing command-scoped `-skipMacroValidation` option on the build and test commands, as already used by the main Hanlin workflow and pinned Markdown consumer. The original app lock identifies Equatable1.4.1 at `597c2bb34af0c51331eb3b5e705f942d8ee20daa`; the native resolver reported that same version. No global Xcode preference, selected package, product source, test selector, gesture, timing, threshold or assertion was changed.

The next native check must execute the original B/C cases before any A or diagnostic D run. This receipt does not turn prior animation failures into passes.

The unchanged [native build log](build-log.txt) retains the resolver output and exact admission diagnostic.

# Native Lists UI query compilation correction

The actual Recovery run46128058948 on5fac built the standalone MiniApps app successfully, then failed while compiling the shared AI_HLYUITests source. No Recovery UI case started. The compiler rejected two expressions in the newly added native Lists helpers because a string subscript returns one XCUIElement, which has no allElementsBoundByIndex property.

This source changes exactly two expressions to enumerate the corresponding button query with matching(identifier:). The original labels, exists/isHittable filters, unique count assertions and later interaction remain unchanged. All42 original test method bodies and every existing assertion/timing line are preserved byte-for-byte. No selector, request, deadline, cache policy, fixture or product source changes.

The earlier source-only review missed this compile API defect. The two original native compiler errors and complete original build logs are retained. Native compilation and UI acceptance of the correction are NOT_RUN; no portable mirror test or extra native run was performed.

The failed run's Git source and tracked prepared overlay are separately bound. The overlay has no shared UI-file change, and the actual compiler printed both failing expressions. A separately retained hash of the compiled UI input was unavailable. The exact same two expressions remained in04 before this correction.

The original six paired routes compile this shared file before selecting individual test methods. The earlierde original90 run and the standalone notification descriptor failure are distinct executions. This proof does not reclassify either one.

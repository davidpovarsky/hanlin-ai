# Original UI08 store isolation

The original two-turn conversational MCP UI case now explicitly enables the existing isolated acceptance store. The method previously reused the default persistent store, allowing prior acceptance rows to be observed before ordinary preload removed and replaced them. The actual failed run displayed the model-info error before reaching the first MCP completion marker; the exact cached model UUID was not logged.

This is one setup argument. The production startup and model-selection paths, helper default, both turns, UI actions, assertions, consent behavior and deadlines remain unchanged. The same application object owns one store UUID for both turns. This case does not cold-reopen the app.

Source review and an exact whole-file inverse check passed. Native execution is still required; later consent and MCP behavior are not inferred from this source correction.

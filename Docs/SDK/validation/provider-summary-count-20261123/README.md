# Provider summary gate fixture count repair

## Actual failure

The provider-summary job [137856126084](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45218713371/job/137856126084) failed two of its eleven Python controls before either affected control reached the summary CLI: the controls required exactly 77 source functions, while the actual catalog contained 78. Its original nine other controls passed; their declarations and inputs are unchanged.

Commit `046c253dc77f78622bac7650b68399ba7e74b4ea` added the real `ProviderRoutingTests.testRepeatedQueryParametersDoNotCrash()` function. Current source inventory is 7 DirectChatPath, 23 Scenario, 12 FaultInjection, 6 LongHorizon, 12 Routing, and 18 Production functions, with no duplicate suite/function identities. The generator correctly discovered all 78. The original failure excerpt is retained unchanged; selection-plan.json binds the original full log hash, current source catalog and control declaration hashes.

## Correction and proof

Only two fixture controls change. Their expected counts now follow the actual nonempty source catalog, while the exact gate behavior remains required. The complete fixture must produce all 78 matching identities with PASS and zero FAIL, NOT_RUN or EVIDENCE_ERROR. The partial fixture omits exactly one declared identity and must fail with 77 PASS, exactly that one NOT_RUN, and zero unrelated failures/evidence errors. The partial fixture requires multiple source functions, preventing an empty or single-item fixture from vacuously satisfying its purpose.

Production summary generation, source discovery, identity matching, gate exit logic, and all actual Swift conformance test methods are byte-identical to the failed run. No assertion threshold or production execution policy is relaxed.

Executed once on Oracle: the two previously failed controls now PASS, 2/2 in 0.213 seconds (0.296239 seconds outer wall time), Python 3.12.3 / Linux aarch64. The other nine controls were not rerun; their original CI outcome remains their evidence. This is controller-fixture verification only: **zero actual provider conformance methods and zero Apple tests executed**.

Exact selection:

```text
python3 -B -m unittest -v
  Scripts.CI.test_generate_provider_conformance_summary.TestGateEnforcement.test_gate_fails_when_one_source_test_not_run
  Scripts.CI.test_generate_provider_conformance_summary.TestGateEnforcement.test_gate_passes_when_all_pass
```

Native application acceptance remains independent of this correction. No CI was dispatched by this task.

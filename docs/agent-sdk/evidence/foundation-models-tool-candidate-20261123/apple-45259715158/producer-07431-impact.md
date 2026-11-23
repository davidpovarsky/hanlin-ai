# Prospective producer07431 impact on the frozen native candidate

This is source analysis, with no new execution, producer pin change or claim that existing e7 outcomes were run against07431.

| Scope | Invocations | Fixture finish reasons | Changed-guard reachability |
|---|---:|---|---|
| Candidate Core normalized native | 2 | toolCalls -> stop(text only) | Completed tool step; shared old/new continuation predicate |
| Candidate Core cloud original | 2 | toolCalls -> stop(text only) | Completed tool step; shared old/new continuation predicate |
| Candidate Core rejected native numbers | 8 | First stream emits toolCalls; no valid second request expected | Invalid call retains input and produces error output. Native stopWhen must reject before next request under either producer. Scheduling may stop earlier. |
| Bridge canonical allow and deny | 2 | toolCalls handoff -> stop(text only) | Same completed-output continuation predicate; no new finish-label branch |
| Bridge invalid numeric sibling | 1 | Bridge throws before emitting any toolCall or finish | No completed-tool step reaches changed guard |
| Bridge cancellation | 1 | Awaiting executor cancelled before response completion | No completed-tool step reaches changed guard |
| Bridge direct doGenerate | 1 | Provider accumulates toolCalls without producer streamText loop | Producer guard bypassed |
| Bridge schema constructor and history rejection | 2 | None | No producer invocation |
| Schema suite | 13 | None | No producer invocation |

None of the32 current cases emits a completed tool step ending in stop. The V3-to-V4 adapter maps unified finish reasons by rawValue. Existing tool handoffs use toolCalls; final stop responses contain no new tool work. The18 schema/history/direct-generate/error-before-handoff/cancellation controls do not exercise the new branch. The other14 cover the shared continuation boundary.

The old baseline12 is authenticated at run45240721804 attempt2 on f311/e7. Its original10 expected failures and2 cloud passes remain separate. The existing strict reuse route must reject a07431 current pin or lock; this analysis does not loosen it.

Original numeric failure counters prove a second provider request in seven f311 cases. They do not constitute a complete event trace, and the remaining passing numeric case does not prove that its stop predicate executed.

Minimum new Hanlin checks after deliberate adoption:

1. Completed allowed original-engine tool with stop finish continues once with exact correlated output and final response.
2. Denied tool with stop finish has zero effect and continues with exact correlated denial.
3. Rejected native numeric tool with stop finish remains providerCalls1 with zero approval/effect.

The planned original-app Calendar acceptance can satisfy matching controls only if its source or retained events establish the non-toolCalls finish label. Upstream budget, missing-output, text-only and tool-error controls should retain their existing provenance/toolchain scope rather than be duplicated automatically. Actual native model eligibility remains separately unresolved.

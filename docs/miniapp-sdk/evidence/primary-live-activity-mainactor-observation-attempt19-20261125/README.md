# MainActor Live Activity observation — actual focused19 compiler failure

The actual focused19 run on a2c8 stopped before any selected case. MiniApps build-for-testing passed; AI build-for-testing exited65 with two strict Swift6.4 isolation errors in the newly authored observation helper. This record preserves all21 original failure packet members, including both complete build logs losslessly compressed. No historical result is changed.

The compiler rejected the task-group closure that captured non-Sendable Activity, then the MainActor iterator sent to the concurrent next() method. The prior source review had not established native compiler validity. Exact diagnostics and their complete original log identity are retained.

The test-only source correction fcfcfb193acbf98e0d77a67be6db88849fd7af8f keeps Activity and each activity.content read on MainActor. A ContinuousClock five-second deadline observes the actual content state, yields via cancellable Task.sleep capped at20ms and the remaining interval, checks cancellation, and returns only the exact requested revision. It does not add unchecked Sendable, unsafe isolation, background tasks, or a fabricated result. This is a condition-based bounded observation, not a fixed sleep followed by an assumed success.

Every byte outside the helper/error case is unchanged. All three test bodies and22 expectations remain, including exact revision2, the same observed ContentState for immutable snapshot loading, Count9/m9, end and reconcile. The corrected source still requires the actual affected native build/run; none was performed by this evidence author.

The exact changed test path is absent from all235 SDK19 source inputs. The source-only commit changes no other path, so the recomputed input identity remains ba8f3f1f09054887eed62532fa1d5ca2ac3bd60e6aa99a98ab1035c7653882a2. SDK19 Host7a426675 and user export1bf34731 are unchanged. Their producer remains a2c8; the corrected consumer is separately recorded as published62dfff9a. No SDK regeneration was performed or required for this test-only change.

The original failed focus charged366.7222996670025 seconds, retained in its original ledger and primary cumulative15839.63407225104. No Mini3 or AI8 case executed; full52 remains separate and unexecuted on this source. Recovery must preserve the original charge and use only the remaining allowance. The earlier actual22/3/0 Mini result and separate19/2/0-of21 AI diagnostic remain immutable.

Validation here was exact source/readback/hash/mode comparison, lossless compression verification, source diff review and diff-check only. No Mac query, compiler, native test, source generator, package download or production-source modification was performed in this lane.

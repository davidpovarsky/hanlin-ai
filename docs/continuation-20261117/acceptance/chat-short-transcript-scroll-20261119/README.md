# Avoid scrolling a fully visible original transcript

Original run44431811538 at e564dc29 has5 passing code-fence cases and6 passing UI cases, with Safari and one-use embedded-result approval failing. Its authenticated full artifact is14496483983 (SHA256 5bd093af27f7421ed8cc2df87d01670c1c26dc16cf2c59c4dd7df687c4159d64).

The original native recordings and synthesized events show the affected transcript moving approximately108points around the failed tap. Safari is completing its response; Skills is still waiting for the same original consent owner. The precise platform/layout cause is not established by those frames alone.

The source always scheduled scrollTo BottomPadding on layout changes, including content that already fit. This commit uses the actual content/viewport/top and bottom inset measurements to require a positive scroll range. Composer clearance is already in the content height. Both initial admission and execution after the existing80ms coalescing wait check the latest range; force does not bypass geometry. The original user/selection/cancellation policy remains. Diagnostics record at most64 content-free layout observations per run.

The existing four coalescing tests retain their assertions and supply measured overflow. Four new tests cover insets, unknown/fitting geometry and forced requests, a pending long-to-short transition, and short-to-long following with the original selection pause. Returning the admitted task lets the shrink test await actual completion without timing sleeps.

Windows Swift6.3.3 parse of all three changed files passed. Native acceptance is NOT_RUN for this commit. Unchanged original Safari, embedded-result consent, partial selection, and search/citation UI cases remain required alongside the complete eight-case scrolling suite. No Markdown dependency, consent callback, deadline, or UI assertion was changed.

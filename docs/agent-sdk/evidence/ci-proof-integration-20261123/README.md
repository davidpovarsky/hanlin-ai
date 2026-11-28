# Central integration of existing CI proof repairs

This integration applies the original e59256e8 paired-proof guard and0f521eab Motion job envelope as patches to the current central head. It does not replace either workflow from an older branch.

The complete Motion workflow is byte-identical to the prior central version after restoring the selected job timeout from35 to25 minutes. The complete paired workflow is byte-identical after removing the new required-reuse environment declaration. Original test bodies, runtime budgets, selection and proof predicates remain unchanged. The existing local21-control result and currently running paired proof-gate PASS retain their original source attribution. No native dispatch or test replay is part of this integration.

# Original Motion job envelope contains its unchanged test allowance

The only workflow change is `jobs.chat-motion-product.timeout-minutes: 25 → 35`. No other job, route, native testcase allowance, assertion, gesture gap, preset or animation timing changes.

Original run45248270552 measured preflight428s + resolution481s + build237s =1146s before testing. Its B case stopped early at35.088s; C ran40.884s, and the complete native job still took1450s of the previous1500s envelope. A successful B continuation must be able to reach its later original scenarios.

The existing runner keeps default testcase allowance600s and maximum720s. The measured1146s preparation plus unchanged720s ceiling plus measured10s result collection =1876s (31m16s), already exceeding25minutes before bookkeeping/upload. The35-minute infrastructure envelope provides224s beyond that arithmetic for bookkeeping, evidence upload and variation. This is a measured planning budget, not a guarantee about future cold-host timing and not a relaxed product criterion.

YAML parsing and semantic comparison PASS: changing only this field back to25 restores the whole parsed workflow exactly. The native runner is byte-identical and its600/720s arguments are retained. The production retention repair remains a separately reviewed parent commit. No native dispatch or native PASS is claimed by this budget change.

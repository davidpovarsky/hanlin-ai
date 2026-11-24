# Original retained-disclosure failure attachment review

Read-only export [45272858701](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45272858701) PASS on exact source 35bfa950, exporting original B from 45267860115. Native inspection job 138036930753 ran 21:58:35–21:58:55Z on runner 1000025054; collector finished 21:59:41Z. No simulator, build or test replay. Original B remains FAIL at line 121 after 44.487626s.

Artifact 14865599937 is 11,426,785 bytes, SHA256 18827fd1472e4212f084592c9a399d97933b2ffca4ad6f8c3db3ace816228cb9. API size/digest and ZIP CRC PASS; all 9 member hashes are retained. Original Xcode video 90224775-0013-46F2-85AC-209D81061983.mp4 is 11,469,795 bytes, SHA256 0723b569d740358bf29bea13418b6a27edc45461f0e671f362cd213432d9c1cd, 432 frames, 42.846667s, 2064×2752. The raw MP4 remains in the authenticated GitHub artifact and Oracle original directory. The two 1891-byte attachments are original synthesized-event NSKeyedArchiver bplists, not accessibility snapshots. No full AX hierarchy or failure screenshot was exported.

## Observed original evidence

At 37.8s the original video displays expanded, actions=1, original multilingual reasoning and nested tool content. At 40.5s it displays collapsed, actions=2, no visible details and the following footer directly below the header. Both show v1.relaxed and shimmer=true/numeric=true. The two JPEGs are explicitly derived crops: ffmpeg decoded the original video at those times, cropped 2064×1300 from 0,0, scaled to 1000px width and encoded JPEG q10. They are visual review aids, not original attachment bytes or AX snapshots.

Original activities show the expanded predicate at 21:37:14.148Z and summary existence check 14.338Z; second tap 14.408Z; collapsed predicate 16.224Z; summary existence check 16.491Z; failure 16.636Z. The original test checks collapsed AX absence after the visual/geometry collapse and fails there. The initial two callback count is visible in video; the later exact baseline assertion and triple burst are NOT_RUN.

## Diagnosis boundary

The retained child is visually collapsed yet its identified summary remains queryable by XCTest. The existing outer custom-Layout accessibilityHidden guard is insufficient in this native configuration. A minimal candidate applies an explicit contain/ignore AX boundary and hidden state to the actual retained child VStack, leaving mounted state, natural-height geometry, clipping, hit testing, animation timing, presets and every original test unchanged. This candidate is not native validated by this export. A+C remains HOLD; no intermediate-reversal PASS is claimed.

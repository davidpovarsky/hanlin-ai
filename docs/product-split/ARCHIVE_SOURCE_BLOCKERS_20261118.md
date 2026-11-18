# Original archive blockers — 2026-11-18

Run 44239527190 at 24237a9a failed before either product reached export. The existing distribution identity passed its resource check; temporary signing material cleanup passed. No device archive, signed IPA, provisioning update, upload or TestFlight success is claimed.

- MiniApps: Xcode reported that its existing scheme was not configured for archive. The application build entry now permits archiving, and a Release ArchiveAction uses that same original target. All test bundles remain excluded from archives.
- Hanlin AI: xcstringstool rejected the RuntimeLocalizable keys "Run Python remotely?" and "Run Python remotely" because punctuation normalization gives the same generated Swift symbol. The confirmation question is now "Run Python on the remote service?"; the action label, existing runtime, provider choice, confirmation and translations remain intact.

Original evidence:
- Artifact 14399841437, API ZIP SHA-256 5614c727c9c031ae296cb95456aecc773280c81c49714bbf278979238c3d806b. Selected ZIP entries have verified CRC and individual SHA-256; the full ZIP digest was not recomputed.
- acceptance.json: 08fed2fe9291f3570a8940c6387af9f52c295c004834538d871b9a605832a539.
- miniapps-archive.log: 448eec104afba6bf5fe97a1e9a7c2af47367b389abf9e22d994d48861323069a.
- ai-archive.log: c620abd810443609458298acc1dd1495342a89bc9e97bd547b692e43a056a9bb.
- Original job log: d259f37ea2f44a871fc434eea1c911eb3785eb4820f02c5473ebe7336254710f.

Both corrections require actual Xcode validation. Stage 2 and Stage 3 remain IN_PROGRESS; release remains NO_GO.

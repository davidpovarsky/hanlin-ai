# Tested source carrier and exact evidence integration

The prepared source that was actually used by both native consumers is now recorded in Git as carrier commit `7f46e9d00fa6b3ef1867c6f174a79b0151a36bcc`, tree `01761ebcbb7109bebd583a59dea4193136d1e721`.

## Source identities

The actual native builds and completed original52/five-runtime cases retain consumer identity `d4a0b115b106d4250ea40ad66153d5156847a07c` plus their authenticated 25 prepared payloads. The SDK export retains producer identity `a2c8a1b1be746461272ba77254603304567c309d`, manifest SHA-256 `4505c28495d8b6ecd1073254e0e395adcc898cc02dd1d40699591f51db4dee92`.

The carrier records those exact already-tested payloads. It is not relabeled as the commit on which the earlier native builds ran. All 25 preimages, working payloads, indexed blobs and committed blobs were checked for their planned SHA-256, byte count and regular-file mode. All 235 SDK source inputs and all 15 current consumer source identities match after materialization.

## Held evidence

Seventeen independent evidence patches were then applied in the exact reviewed order. They add 1,587 disjoint regular evidence files, with each applied blob/tree checked against its original held commit. The resulting evidence head is `a42e15aecbe7178bb4095bf071f13ee0b3bbfeeb`.

The original-to-applied commit mapping is retained in [held-evidence-integration-receipt.json](held-evidence-integration-receipt.json). No unlisted historical parent was assumed to be a target ancestor. These additions do not overlap the prepared payloads, SDK source inputs or consumer source inputs.

The existing AGENTS.md change and both node_modules entries were retained. The index was empty on entry and after each completed phase. Protected file/link identities match their initial snapshot.

## Retained execution records

The two exact applied scripts and their input plans/receipts are included here. The scripts are audit records with fixed historical preconditions; they are not general installation instructions and must not be blindly rerun.

This integration performed no SDK regeneration, package resolution, native compilation, native test or product installation. The matching full52, five-runtime, repair, coverage and other result packets retain their own actual execution identities and boundaries.

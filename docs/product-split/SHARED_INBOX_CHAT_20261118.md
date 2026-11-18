# Shared inbox into the original chat — 2026-11-18

Source status: implemented; Apple compilation and native acceptance pending.

SYS-02 previously saved ingress batches and delivered MiniApp actions, but the original chat could not choose an existing batch. The Composer + menu now opens the original Shared Items screen. Choosing Add to draft appends the batch's text and links and verified file copies to the existing draft. It does not create a new conversation, send a message, execute a tool, or consume/delete the source batch.

The existing App Group, HanlinShareInboxStore, Composer bindings, ChatMessages document processing, Agent SDK and HTTP request path remain the implementation. No new agent or permission/storage engine is added.

The entire batch must be readable and fit the existing five-file limit. Copying runs on the inbox actor with cancellation checks, no-link regular-file reads, exclusive private destinations and verification of the bytes actually copied against the original hash and length. Failed or cancelled preparation removes only its operation-owned files. A different conversation or a responding chat rejects completion before mutation. Accepted files live in private application support because original message records retain their URLs. Filenames are limited to a leaf and retain their type extension.

Native tests cover the actual original App Group, mixed text/link/file, source preservation, capacity, rejected and tampered input, and cancellation. The UI case verifies cancel preserves an existing draft, add does not contact the model, the actual request contains original draft text plus all shared content, and the saved reply survives process relaunch. Only model HTTP is scripted. Fixture input uses real original store APIs; this is explicitly not proof of presenting the OS share sheet.

The existing paired runner has separate exact scopes: cross_product still requires all three original product scenarios; shared_ingress requires four native host tests plus one UI scenario. Both scopes still build both original products, verify signatures, inspect embedded simulator entitlements, and require the OS-provided group containers to match.

Seven source/test files passed Swift syntax parsing. This is not Apple compilation or a native test PASS. Original catalogue entries were preserved; seven new strings have English, Hebrew and Simplified Chinese translations.

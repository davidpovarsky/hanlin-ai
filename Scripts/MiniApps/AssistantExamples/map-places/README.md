# Map places assistant example

This complete NativeScript authoring project uses local, fictional fixtures. It makes no network request and does not claim real restaurant or museum listings.

Build with the host's current SDK using the public CLI, Scripts/MiniApps/miniapp.mjs. Attach **Nearby places — local demo** in chat, choose the map pin/radius and categories, then send a query such as “restaurant”. Selecting/configuring only changes the draft. The tool receives the immutable map values in its separate context when the model calls search.

The ordinary app entry remains index.ts. The places.ts module is compiled into a dedicated assistant program and imports no app entry. See the exported docs/miniapp-sdk/ASSISTANT_TOOLS_AND_COMPOSER.md for the full contract.

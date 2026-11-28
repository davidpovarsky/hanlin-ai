// Consume the shipped package.json/types entry, not Scripts/NativeScript/host-services.ts.
import {
  createHostServices, type MiniAppAssistant
} from '../../../../Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptRuntime/Resources/NativeScriptSharedRuntime/@hanlin/host-services';

const host = createHostServices();
const assistant: MiniAppAssistant = host.assistant;
void assistant.generate({messages: [{role: 'user', content: 'typed packaged facade'}]});
// A missing declaration must not silently erase the public assistant type.
// @ts-expect-error The original assistant facade is not a numeric value.
const invalidAssistant: number = host.assistant;
void invalidAssistant;

host.registerRequestHandler('probe', 'inter-app.share', async ({caller, parameters}) => ({caller, parameters}));
// @ts-expect-error An action result must remain a canonical JSON value.
host.registerRequestHandler('invalid', 'inter-app.share', () => undefined);
// @ts-expect-error Action metadata keeps the declared capability typed.
host.registerRequestHandler('invalid', 42, () => null);

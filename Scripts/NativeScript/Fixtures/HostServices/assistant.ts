import {createHostServices, type MiniAppAssistantRequest, type MiniAppAssistantEvent} from '../../host-services';

async function example() {
  const assistant = createHostServices().assistant;
  const models = await assistant.models();
  const request: MiniAppAssistantRequest = {
    model: models[0]?.id,
    conversationID: 'document-review',
    system: 'Review the supplied document.',
    messages: [{role: 'user', content: [{type: 'text', text: 'What is shown?'}, {type: 'image', url: 'https://example.test/image.png'}]}],
  };
  for await (const event of assistant.stream(request)) {
    const actual: MiniAppAssistantEvent = event;
    if (actual.type === 'finish') console.log(actual.usage.cachedInputTokens, actual.usage.cacheWriteTokens);
  }
  const result = await assistant.generate({...request, responseSchema: {
    type: 'object', properties: {summary: {type: 'string'}}, required: ['summary'], additionalProperties: false,
  }});
  console.log(result.value);
  const run = await assistant.start(request);
  await run.cancel();
}

void example;

// The shared API deliberately offers neither raw credentials nor implicit host tools.
const invalid: MiniAppAssistantRequest = {
  messages: [{role: 'user', content: 'Hello'}],
  // @ts-expect-error Credentials belong to the original native provider registry.
  apiKey: 'not-a-supported-option',
};
void invalid;

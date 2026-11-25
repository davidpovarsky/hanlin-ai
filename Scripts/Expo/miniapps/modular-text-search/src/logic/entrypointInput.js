/** Normalize inputs supplied by Shortcuts, Translation and the owned Share Inbox. */
export function normalizeEntrypointInput(parameters) {
  if (typeof parameters === 'string') return { query: parameters.trim() };
  if (!parameters || typeof parameters !== 'object' || Array.isArray(parameters)) return { query: '' };
  const direct = parameters.query ?? parameters.text ?? parameters.inputText ?? parameters.shortcutParameter;
  let query = typeof direct === 'string' ? direct.trim() : '';
  if (!query && Array.isArray(parameters.items)) {
    query = parameters.items.map(item => {
      if (!item || typeof item !== 'object') return '';
      return typeof item.text === 'string' ? item.text : typeof item.url === 'string' ? item.url : '';
    }).filter(Boolean).join('\n').trim();
  }
  const locale = parameters.locale === 'he' || parameters.locale === 'en' ? parameters.locale : undefined;
  return { query, ...(locale ? { locale } : {}) };
}

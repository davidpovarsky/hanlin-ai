import mermaid from 'mermaid';
import {parse, html} from 'diff2html';
let diagramSequence = 0;

// Called only by native structured callAsyncJavaScript arguments. The source
// is data for the maintained parsers, never JavaScript or interpolated HTML.
window.hanlinRenderCodeFence = async function ({kind, source, dark = false, fontSize = 16, split = false}) {
  if (typeof source !== 'string' || source.length > 1_048_576) throw new Error('Source exceeds the local rendering budget.');
  if (!['mermaid', 'diff'].includes(kind)) throw new Error('Unsupported code language.');
  const size = Math.max(12, Math.min(28, Number(fontSize) || 16));
  document.documentElement.style.fontSize = size + 'px';
  document.documentElement.dataset.appearance = dark ? 'dark' : 'light';
  const host = document.getElementById('render-host');
  host.replaceChildren();
  let markup, files = 0;
  if (kind === 'mermaid') {
    mermaid.initialize({
      startOnLoad: false, securityLevel: 'strict', suppressErrorRendering: true, logLevel: 'fatal',
      theme: dark ? 'dark' : 'default', htmlLabels: false,
      fontFamily: '-apple-system, BlinkMacSystemFont, sans-serif', fontSize: size,
      maxTextSize: 200_000, maxEdges: 1_000,
      flowchart: {htmlLabels: false, useMaxWidth: false}, sequence: {useMaxWidth: false},
      secure: ['secure', 'securityLevel', 'startOnLoad', 'maxTextSize', 'maxEdges', 'suppressErrorRendering',
        'themeCSS', 'dompurifyConfig', 'htmlLabels', 'flowchart', 'sequence', 'fontFamily', 'fontSize']
    });
    const result = await mermaid.render('hanlin-diagram-' + (++diagramSequence), source);
    markup = result.svg;
  } else {
    const parsed = parse(source, {diffMaxChanges: 10_000, diffMaxLineLength: 100_000});
    if (!parsed.length || parsed.some(file => !file.blocks.length && !file.isBinary && !file.isRename && !file.isCopy)) {
      throw new Error('The source is not a supported complete unified diff.');
    }
    files = parsed.length;
    const changes = parsed.reduce((sum, file) => sum + file.addedLines + file.deletedLines, 0);
    markup = html(parsed, {drawFileList: false, outputFormat: split ? 'side-by-side' : 'line-by-line',
      matching: source.length < 40_000 && changes < 500 ? 'lines' : 'none', diffStyle: 'word',
      colorScheme: dark ? 'dark' : 'light', renderNothingWhenEmpty: true});
  }
  // The maintained engines escape/sanitize their own output. This additional
  // DOM boundary removes active elements, handlers and external references.
  const template = document.createElement('template');
  template.innerHTML = markup;
  for (const node of template.content.querySelectorAll('script,iframe,object,embed,form,input,button,meta,link,foreignObject')) node.remove();
  for (const node of template.content.querySelectorAll('*')) {
    for (const attribute of [...node.attributes]) {
      const name = attribute.name.toLowerCase(), value = attribute.value.trim();
      if (name.startsWith('on') || ['src', 'srcset', 'action', 'formaction'].includes(name)
          || (['href', 'xlink:href'].includes(name) && !value.startsWith('#'))) node.removeAttribute(attribute.name);
    }
  }
  if (kind === 'mermaid') {
    const svg = template.content.querySelector('svg'), bounds = svg?.viewBox?.baseVal;
    if (!bounds || bounds.width <= 0 || bounds.height <= 0 || bounds.width > 20_000 || bounds.height > 20_000) {
      throw new Error('Diagram geometry exceeds the local rendering budget.');
    }
    // Mermaid families differ in their percent-width defaults. Keep natural
    // SVG dimensions so a narrow state/class graph never inflates its text to
    // fill the viewport. Each render also has an isolated CSS/marker identity.
    svg.setAttribute('width', String(Math.ceil(bounds.width)));
    svg.setAttribute('height', String(Math.ceil(bounds.height)));
    svg.style.maxWidth = 'none';
  }
  host.append(template.content);
  const result = {kind, html: host.innerHTML, files,
    width: Math.ceil(Math.max(host.scrollWidth, host.getBoundingClientRect().width)),
    height: Math.ceil(Math.max(host.scrollHeight, host.getBoundingClientRect().height))};
  host.replaceChildren();
  return result;
};

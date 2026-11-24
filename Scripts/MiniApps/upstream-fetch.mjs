// Shared HTTP transport for exact upstream inputs. Authentication changes only
// how GitHub serves an input; its immutable URL and digest checks remain owned
// by the resolver/refresher callers.
const userAgent = 'Hanlin-MiniApp-Upstream-Resolver';

function diagnostic(value, secrets) {
  let text = String(value);
  for (const secret of secrets) text = text.split(secret).join('[redacted]');
  return text.replace(/[\r\n\t]+/g, ' ').slice(0, 600);
}

export async function fetchOriginalResponse(url, {timeoutMs = 60000, accept} = {}) {
  const location = new URL(url);
  const githubAPI = location.origin === 'https://api.github.com';
  const secrets = [process.env.GH_TOKEN, process.env.GITHUB_TOKEN]
    .map(value => value?.trim()).filter(Boolean);
  const headers = {'User-Agent': userAgent};
  if (accept) headers.Accept = accept;
  if (githubAPI) {
    headers.Accept = 'application/vnd.github+json';
    // Use the job's existing GitHub credential only with the intended API.
    // Raw source CDNs, npm publications and artifact hosts remain unchanged.
    if (secrets[0]) headers.Authorization = `Bearer ${secrets[0]}`;
  }
  const response = await fetch(url, {headers, signal: AbortSignal.timeout(timeoutMs)});
  if (!response.ok) {
    const details = [];
    if (githubAPI) {
      try {
        const body = await response.json();
        if (typeof body.message === 'string') details.push(diagnostic(body.message, secrets));
      } catch { /* Status and response headers still identify a non-JSON failure. */ }
      for (const name of ['x-ratelimit-remaining', 'x-ratelimit-reset', 'retry-after']) {
        const value = response.headers.get(name);
        if (value && /^\d+$/.test(value)) details.push(`${name}=${value}`);
      }
    }
    location.username = ''; location.password = '';
    for (const name of [...location.searchParams.keys()]) {
      if (/token|signature|credential|secret|authorization|api[_-]?key/i.test(name)) {
        location.searchParams.set(name, '[redacted]');
      }
    }
    throw new Error(`Original source fetch failed (${response.status}): ${diagnostic(location, secrets)}` +
      (details.length ? `; ${details.join('; ')}` : ''));
  }
  return response;
}

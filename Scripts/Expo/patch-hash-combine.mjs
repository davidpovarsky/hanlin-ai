import { readFileSync, writeFileSync, readdirSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';

const compat = `#if defined(__cpp_concepts) && __cpp_concepts >= 201907L
template <typename T>
concept Hashable = !std::is_same_v<T, const char *> && (requires(T a) {
  { std::hash<T>{}(a) } -> std::convertible_to<std::size_t>;
});

template <Hashable T, Hashable... Rest>
void hash_combine(std::size_t &seed, const T &v, const Rest &...rest)
{
  seed ^= std::hash<T>{}(v) + 0x9e3779b9 + (seed << 6) + (seed >> 2);
  (hash_combine(seed, rest), ...);
}

template <Hashable T, Hashable... Args>
std::size_t hash_combine(const T &v, const Args &...args)
{
  std::size_t seed = 0;
  hash_combine<T, Args...>(seed, v, args...);
  return seed;
}

template <Hashable... Ts>
  requires(sizeof...(Ts) <= 32)
void hash_combine_optionals(std::size_t &seed, const std::optional<Ts> &...optionals)
{
  std::uint32_t presence = 0;
  std::uint32_t bit = 1;
  ((presence |= optionals.has_value() ? bit : 0u, bit <<= 1), ...);
  std::size_t optionalsSeed = presence;

  auto combineIfEngaged = [&optionalsSeed](const auto &optional) {
    if (optional.has_value()) {
      hash_combine(optionalsSeed, *optional);
    }
  };
  (combineIfEngaged(optionals), ...);
  hash_combine(seed, optionalsSeed);
}
#else
template <typename T, typename... Rest>
void hash_combine(std::size_t &seed, const T &v, const Rest &...rest)
{
  seed ^= std::hash<T>{}(v) + 0x9e3779b9 + (seed << 6) + (seed >> 2);
  if constexpr (sizeof...(rest) > 0) {
    hash_combine(seed, rest...);
  }
}

template <typename T, typename... Args>
std::size_t hash_combine(const T &v, const Args &...args)
{
  std::size_t seed = 0;
  hash_combine(seed, v, args...);
  return seed;
}

template <typename... Ts>
void hash_combine_optionals(std::size_t &seed, const std::optional<Ts> &...optionals)
{
  std::uint32_t presence = 0;
  std::uint32_t bit = 1;
  ((presence |= optionals.has_value() ? bit : 0u, bit <<= 1), ...);
  std::size_t optionalsSeed = presence;

  auto combineIfEngaged = [&optionalsSeed](const auto &optional) {
    if (optional.has_value()) {
      hash_combine(optionalsSeed, *optional);
    }
  };
  (combineIfEngaged(optionals), ...);
  hash_combine(seed, optionalsSeed);
}
#endif

} // namespace facebook::react`;

function patchAll(dir) {
  if (!existsSync(dir)) return;
  for (const ent of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, ent.name);
    if (ent.isDirectory()) {
      patchAll(full);
    } else if (ent.name === 'hash_combine.h') {
      let content = readFileSync(full, 'utf8');
      if (content.includes('concept Hashable') && !content.includes('__cpp_concepts')) {
        content = content.replace(
          /template <typename T>\s*concept Hashable[\s\S]*?\}\s*\/\/\s*namespace facebook::react/,
          compat
        );
        writeFileSync(full, content, 'utf8');
        console.log('Successfully patched hash_combine.h at:', full);
      }
    }
  }
}

const targets = process.argv.slice(2);
if (targets.length === 0) {
  targets.push(resolve(process.cwd(), 'Packages/HanlinExpoRuntime/Artifacts'));
}
for (const t of targets) {
  const fullTarget = resolve(process.cwd(), t);
  if (existsSync(fullTarget)) {
    console.log('[HanlinExpo] Scanning and patching hash_combine.h in:', fullTarget);
    patchAll(fullTarget);
  }
}
console.log('Done scanning and patching hash_combine.h');

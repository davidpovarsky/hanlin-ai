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
      if (ent.name === 'folly') {
        const jsonDyn = join(full, 'json', 'dynamic.h');
        const dyn = join(full, 'dynamic.h');
        if (existsSync(jsonDyn)) {
          writeFileSync(dyn, readFileSync(jsonDyn, 'utf8'), 'utf8');
          console.log('Copied full folly/json/dynamic.h to:', dyn);
        } else if (existsSync(dyn)) {
          const jsonDir = join(full, 'json');
          if (!existsSync(jsonDir)) mkdirSync(jsonDir, { recursive: true });
          writeFileSync(jsonDyn, readFileSync(dyn, 'utf8'), 'utf8');
          console.log('Copied full folly/dynamic.h to:', jsonDyn);
        }
      }
      patchAll(full);
    } else if (ent.name === 'ExpoModulesCore_umbrella.h') {
      let content = readFileSync(full, 'utf8');
      const filtered = content
        .replace(/^[ \t]*#import[ \t]+"ExpoViewComponentDescriptor\.h"[ \t]*\r?\n?/gm, '')
        .replace(/^[ \t]*#import[ \t]+"ExpoViewEventEmitter\.h"[ \t]*\r?\n?/gm, '')
        .replace(/^[ \t]*#import[ \t]+"ExpoViewProps\.h"[ \t]*\r?\n?/gm, '')
        .replace(/^[ \t]*#import[ \t]+"ExpoViewShadowNode\.h"[ \t]*\r?\n?/gm, '')
        .replace(/^[ \t]*#import[ \t]+"ExpoViewState\.h"[ \t]*\r?\n?/gm, '')
        .replace(/^[ \t]*#import[ \t]+"SwiftUIViewProps\.h"[ \t]*\r?\n?/gm, '')
        .replace(/^[ \t]*#import[ \t]+"ExpoFabricViewObjC\.h"[ \t]*\r?\n?/gm, '')
        .replace(/^[ \t]*#import[ \t]+"EXHostWrapper\.h"[ \t]*\r?\n?/gm, '')
        .replace(/^[ \t]*#import[ \t]+"TestingSyncJSCallInvoker\.h"[ \t]*\r?\n?/gm, '');
      if (filtered !== content) {
        writeFileSync(full, filtered, 'utf8');
        console.log('Sanitized ExpoModulesCore_umbrella.h at:', full);
      }
    } else if (ent.name === 'ExpoModulesCore.h') {
      let content = readFileSync(full, 'utf8');
      const filtered = content
        .replace(/^[ \t]*#import[ \t]+<ExpoModulesCore\/SwiftUIViewProps\.h>[ \t]*\r?\n?/gm, '')
        .replace(/^[ \t]*#import[ \t]+"SwiftUIViewProps\.h"[ \t]*\r?\n?/gm, '')
        .replace(/^[ \t]*#import[ \t]+<ExpoModulesCore\/ExpoFabricViewObjC\.h>[ \t]*\r?\n?/gm, '')
        .replace(/^[ \t]*#import[ \t]+"ExpoFabricViewObjC\.h"[ \t]*\r?\n?/gm, '')
        .replace(/^[ \t]*#import[ \t]+<ExpoModulesCore\/EXHostWrapper\.h>[ \t]*\r?\n?/gm, '')
        .replace(/^[ \t]*#import[ \t]+"EXHostWrapper\.h"[ \t]*\r?\n?/gm, '');
      if (filtered !== content) {
        writeFileSync(full, filtered, 'utf8');
        console.log('Sanitized ExpoModulesCore.h at:', full);
      }
    } else if (ent.name === 'RawProps.h') {
      let content = readFileSync(full, 'utf8');
      if (content.includes('#include <folly/dynamic.h>') && !content.includes('__has_include(<folly/dynamic.h>)')) {
        content = content.replace(
          '#include <folly/dynamic.h>',
          `#if __has_include(<folly/dynamic.h>)
#include <folly/dynamic.h>
#elif __has_include(<folly/json/dynamic.h>)
#include <folly/json/dynamic.h>
#endif`
        );
        writeFileSync(full, content, 'utf8');
        console.log('Sanitized RawProps.h at:', full);
      }
    } else if (ent.name === 'EXHostWrapper.h') {
      let content = readFileSync(full, 'utf8');
      if (content.includes('#import <ReactCommon/RCTHost.h>') && !content.includes('@class RCTHost;')) {
        const replacement = `#if __has_include(<ReactCommon/RCTHost.h>)
#import <ReactCommon/RCTHost.h>
#elif __has_include("ReactCommon/RCTHost.h")
#import "ReactCommon/RCTHost.h"
#elif __has_include(<React/RCTHost.h>)
#import <React/RCTHost.h>
#else
@class RCTHost;
#endif`;
        content = content.replace('#import <ReactCommon/RCTHost.h>', replacement);
        writeFileSync(full, content, 'utf8');
        console.log('Sanitized EXHostWrapper.h at:', full);
      }
    } else if (ent.name === 'TestingSyncJSCallInvoker.h') {
      let content = readFileSync(full, 'utf8');
      if (content.includes('#include <ReactCommon/CallInvoker.h>') && !content.includes('__has_include(<ReactCommon/CallInvoker.h>)')) {
        const replacement = `#if __has_include(<ReactCommon/CallInvoker.h>)
#include <ReactCommon/CallInvoker.h>
#elif __has_include("ReactCommon/CallInvoker.h")
#include "ReactCommon/CallInvoker.h"
#elif __has_include(<React/CallInvoker.h>)
#include <React/CallInvoker.h>
#endif`;
        content = content.replace('#include <ReactCommon/CallInvoker.h>', replacement);
        writeFileSync(full, content, 'utf8');
        console.log('Sanitized TestingSyncJSCallInvoker.h at:', full);
      }
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
    } else if (ent.name === 'react_native_assert.h') {
      let content = readFileSync(full, 'utf8');
      if (content.includes('#include <glog/logging.h>') && !content.includes('__has_include(<glog/logging.h>)')) {
        content = content.replace(
          '#include <glog/logging.h>',
          '#if __has_include(<glog/logging.h>)\n#include <glog/logging.h>\n#else\n#define GLOG_NO_ABBREVIATED_SEVERITIES\n#endif'
        );
        content = content.replace(
          '#define react_native_assert(cond)',
          '#if !__has_include(<glog/logging.h>)\n#define react_native_assert(cond) assert(cond)\n#else\n#define react_native_assert(cond)'
        );
        content = content.replace(
          /  \}\r?\n\r?\n#endif \/\/ platforms besides __ANDROID__/,
          '  }\n#endif\n\n#endif // platforms besides __ANDROID__'
        );
        writeFileSync(full, content, 'utf8');
        console.log('Successfully patched react_native_assert.h at:', full);
      }
    } else if (ent.name === 'fnv1a.h') {
      let content = readFileSync(full, 'utf8');
      if (content.includes('std::identity') && !content.includes('fnv1a_identity')) {
        const replacement = `#if defined(__cpp_lib_identity) || (defined(__cplusplus) && __cplusplus >= 202002L)
template <typename CharTransformT = std::identity>
#else
struct fnv1a_identity {
  template <typename T>
  constexpr auto&& operator()(T&& val) const noexcept {
    return static_cast<T&&>(val);
  }
};
template <typename CharTransformT = fnv1a_identity>
#endif`;
        content = content.replace('template <typename CharTransformT = std::identity>', replacement);
        writeFileSync(full, content, 'utf8');
        console.log('Successfully patched fnv1a.h at:', full);
      }
    } else if (ent.name.endsWith('.h')) {
      let content = readFileSync(full, 'utf8');
      let changed = false;
      if (content.includes('#include <folly/dynamic.h>') && !content.includes('__has_include(<folly/dynamic.h>)')) {
        const replacement = `#if __has_include(<folly/dynamic.h>)
#include <folly/dynamic.h>
#elif __has_include(<folly/json/dynamic.h>)
#include <folly/json/dynamic.h>
#else
#include <folly/dynamic.h>
#endif`;
        content = content.replace(/#include <folly\/dynamic\.h>/g, replacement);
        changed = true;
      }
      if (content.includes('#include <jsi/JSIDynamic.h>') && !content.includes('__has_include(<jsi/JSIDynamic.h>)')) {
        const replacement = `#if __has_include(<jsi/JSIDynamic.h>)
#include <jsi/JSIDynamic.h>
#endif`;
        content = content.replace(/#include <jsi\/JSIDynamic\.h>/g, replacement);
        changed = true;
      }
      if (changed) {
        writeFileSync(full, content, 'utf8');
        console.log('Successfully patched dynamic includes at:', full);
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

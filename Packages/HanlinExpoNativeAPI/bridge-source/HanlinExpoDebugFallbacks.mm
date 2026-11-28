//
//  HanlinExpoDebugFallbacks.mm
//  HanlinExpoNativeAPICore
//
//  Fallback definitions for React Native ShadowNode debug string convertible methods.
//  When linking against release prebuilt React.xcframework in debug test runs,
//  this provides exported weak definitions so dyld never fails symbol resolution.
//

#include <string>
#include <vector>
#include <memory>

namespace facebook {
namespace react {

class DebugStringConvertible;

class ShadowNode {
public:
  std::string getDebugName() const;
  std::string getDebugValue() const;
  std::vector<std::shared_ptr<const DebugStringConvertible>> getDebugChildren() const;
  std::vector<std::shared_ptr<const DebugStringConvertible>> getDebugProps() const;
};

__attribute__((visibility("default"), weak))
std::string ShadowNode::getDebugName() const {
  return "ShadowNode";
}

__attribute__((visibility("default"), weak))
std::string ShadowNode::getDebugValue() const {
  return "";
}

__attribute__((visibility("default"), weak))
std::vector<std::shared_ptr<const DebugStringConvertible>> ShadowNode::getDebugChildren() const {
  return {};
}

__attribute__((visibility("default"), weak))
std::vector<std::shared_ptr<const DebugStringConvertible>> ShadowNode::getDebugProps() const {
  return {};
}

} // namespace react
} // namespace facebook

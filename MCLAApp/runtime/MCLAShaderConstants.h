#pragma once
#include <array>
#include <cstdint>
#include <cstring>
#include <optional>
#include <span>
#include <vector>

namespace mcla::native {
struct ShaderFloatDefinition {
  uint32_t destination; // Byte offset within the stage's float constant bank.
  uint32_t source;      // Relative to the shader object's physical base.
  uint32_t bytes;
};
// Draw submission uses caller-owned storage. Guest memory can change, so any
// decoded-table reuse must validate the actual bytes, not shader addresses.
inline bool DecodeShaderFloatDefinitionsInto(
    std::span<const uint8_t> bytes, uint32_t firstRegister,
    std::span<ShaderFloatDefinition> output, size_t& count) {
  count = 0;
  if (firstRegister != 0 && firstRegister != 256) return false;
  for (size_t cursor = 0; cursor + 4 <= bytes.size();) {
    const auto* p = bytes.data() + cursor;
    const uint32_t reg = (uint32_t(p[0]) << 8) | p[1];
    const uint32_t words = (uint32_t(p[2]) << 8) | p[3];
    if (!words) return true;
    if (cursor + 8 > bytes.size() || reg < firstRegister ||
        reg - firstRegister >= 256 ||
        words > 1024 - (reg - firstRegister) * 4 ||
        count >= output.size()) return false;
    const uint32_t source = (uint32_t(p[4]) << 24) |
                            (uint32_t(p[5]) << 16) |
                            (uint32_t(p[6]) << 8) | p[7];
    if (source & 3) return false;
    output[count++] = {(reg - firstRegister) * 16, source, words * 4};
    cursor += 8;
  }
  return false;
}
// The parser consumes at most 256 eight-byte entries and a four-byte
// terminator. Other sections after that terminator are not float definitions.
// Keep one exact, bounded snapshot per stage/thread, while source constants
// and their address/range validation remain live on every draw.
class ShaderDefinitionSnapshot {
  std::array<uint8_t,256*8+4> bytes_{};
  std::array<ShaderFloatDefinition,256> definitions_{};
  size_t consumed_=0, count_=0;
  uint32_t firstRegister_=0;
  bool valid_=false;
  uint64_t hits_=0, decodes_=0;
public:
  bool Resolve(std::span<const uint8_t> bytes,uint32_t firstRegister,
               std::span<const ShaderFloatDefinition>& result) {
    result={};
    if (valid_ && firstRegister_==firstRegister && bytes.size()>=consumed_ &&
        std::memcmp(bytes_.data(),bytes.data(),consumed_)==0) {
      ++hits_; result={definitions_.data(),count_}; return true;
    }
    valid_=false;
    ++decodes_;
    if (!DecodeShaderFloatDefinitionsInto(bytes,firstRegister,definitions_,count_))
      return false;
    consumed_=count_*8+4;
    std::memcpy(bytes_.data(),bytes.data(),consumed_);
    firstRegister_=firstRegister; valid_=true;
    result={definitions_.data(),count_}; return true;
  }
  void Reset() { valid_=false; }
  uint64_t hits() const { return hits_; }
  uint64_t decodes() const { return decodes_; }
};
// CE sub_82424480 consumes the first section of the shader definition table:
// BE16 register, BE16 dword count, BE32 physical offset; count zero ends it.
// It emits LOAD_ALU_CONSTANT, never updating the CPU device shadow. Recreate
// that immutable shader-owned state in the native snapshot, not guest RAM.
inline std::optional<std::vector<ShaderFloatDefinition>> DecodeShaderFloatDefinitions(
    std::span<const uint8_t> bytes,uint32_t firstRegister) {
  std::vector<ShaderFloatDefinition> result;
  result.resize(256);
  size_t count = 0;
  if (!DecodeShaderFloatDefinitionsInto(bytes, firstRegister, result, count))
    return std::nullopt;
  result.resize(count);
  return result;
}
}

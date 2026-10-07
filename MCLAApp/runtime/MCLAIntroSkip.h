#pragma once
#include <cstdint>
#include <span>
namespace mcla::native {
// The normal legals/movie constructor creates the SWF player at +4 and its
// context. Byte +13 is the game's own skip request, consumed by 821F9918.
// Preserve the constructor, timer, render state and completion flags.
inline bool RequestInitializedIntroSkip(std::span<uint8_t> object) {
  if(object.size()<16)return false;
  if(!(object[4]|object[5]|object[6]|object[7]))return false;
  object[13]=1;return true;
}
}

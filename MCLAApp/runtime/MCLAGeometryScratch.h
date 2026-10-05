#pragma once
#include <cstdint>
#include <cstring>
#include <vector>

namespace mcla::metal {
// Renderer commands are serialized. A lease keeps staging bytes alive until
// Metal has copied them into an immutable upload; early returns also trim
// oversized allocations. These vectors never back GPU resources directly.
template <class T> class GeometryScratch {
  std::vector<T> values_;
  size_t retainedBytes_;
  uint64_t growths_=0, uses_=0;
public:
  explicit GeometryScratch(size_t retainedBytes):retainedBytes_(retainedBytes) {}
  class Lease {
    GeometryScratch& owner_;
    bool reuse_;
    size_t initialCapacity_;
  public:
    Lease(GeometryScratch& owner,size_t size,bool reuse):owner_(owner),reuse_(reuse),
        initialCapacity_(owner.values_.capacity()) {
      ++owner_.uses_;
      owner_.values_.resize(size);
    }
    Lease(const Lease&)=delete;
    Lease& operator=(const Lease&)=delete;
    ~Lease() {
      if (owner_.values_.capacity()>initialCapacity_) ++owner_.growths_;
      if (!reuse_ || owner_.values_.capacity()>owner_.retainedBytes_/sizeof(T))
        std::vector<T>().swap(owner_.values_);
    }
    std::vector<T>& values() { return owner_.values_; }
  };
  Lease Use(size_t size,bool reuse=true) { return Lease(*this,size,reuse); }
  size_t capacity() const { return values_.capacity(); }
  uint64_t growths() const { return growths_; }
  uint64_t uses() const { return uses_; }
};

// Match the original zero-initialized vector plus full-word endian swap,
// including zero trailing bytes when a payload is not a multiple of four.
inline void SwapVertexWords(uint8_t* dst,const uint8_t* src,size_t bytes) {
  size_t i=0;
  for (;i+4<=bytes;i+=4) {
    uint32_t word; std::memcpy(&word,src+i,4);
    word=__builtin_bswap32(word); std::memcpy(dst+i,&word,4);
  }
  if (i<bytes) std::memset(dst+i,0,bytes-i);
}
} // namespace mcla::metal

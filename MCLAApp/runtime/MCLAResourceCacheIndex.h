#pragma once
#include <cassert>
#include <array>
#include <cstddef>
#include <cstdint>
#include <iterator>
#include <list>
#include <optional>
#include <unordered_map>
#include <unordered_set>

namespace mcla::metal {
// CPU-only metadata, owned by the serialized renderer. The renderer's value
// maps still own Metal objects; normal command-buffer retention owns in-flight
// GPU references. No iterators into a rehashable unordered_map are persisted.
class ResourceCacheIndex {
  using Key = uint64_t;
  struct Age { Key key; uint64_t frame; };
  using Ages = std::list<Age>;
  struct Entry {
    Ages::iterator age;
    std::unordered_set<uint32_t> owners;
    std::unordered_set<uint64_t> aliases;
  };
  Ages ages_;
  std::unordered_map<Key,Entry> entries_;
  std::unordered_map<uint32_t,std::unordered_set<Key>> owners_;
  std::unordered_map<uint64_t,Key> aliases_;
public:
  // Entry iterators refer into ages_; accidental copies would invalidate them.
  ResourceCacheIndex() = default;
  ResourceCacheIndex(const ResourceCacheIndex&) = delete;
  ResourceCacheIndex& operator=(const ResourceCacheIndex&) = delete;
  void Touch(Key key, uint64_t frame) {
    auto entry = entries_.find(key);
    if (entry == entries_.end()) {
      assert(ages_.empty() || ages_.back().frame <= frame);
      ages_.push_back({key,frame});
      entries_.emplace(key,Entry{std::prev(ages_.end()),{}, {}});
    } else if (entry->second.age->frame != frame) {
      assert(ages_.empty() || ages_.back().frame <= frame);
      entry->second.age->frame = frame;
      ages_.splice(ages_.end(),ages_,entry->second.age);
    }
  }
  void AddOwner(Key key, uint32_t owner) {
    auto entry=entries_.find(key);assert(entry!=entries_.end());
    if (entry->second.owners.insert(owner).second) owners_[owner].insert(key);
  }
  void BindAlias(Key key, uint64_t alias) {
    auto entry=entries_.find(key);assert(entry!=entries_.end());
    auto previous=aliases_.find(alias);
    if (previous!=aliases_.end()) {
      if (previous->second==key) return;
      // Wrapper reuse can rebind an alias without evicting its old content.
      entries_.at(previous->second).aliases.erase(alias);
      previous->second=key;
    } else aliases_.emplace(alias,key);
    entry->second.aliases.insert(alias);
  }
  std::optional<Key> FindAlias(uint64_t alias) const {
    auto it=aliases_.find(alias);
    return it==aliases_.end()?std::nullopt:std::optional<Key>(it->second);
  }
  std::optional<Key> FirstOwned(uint32_t owner) const {
    auto it=owners_.find(owner);
    return it==owners_.end()?std::nullopt:std::optional<Key>(*it->second.begin());
  }
  std::optional<Key> Expired(uint64_t cutoff) const {
    return !ages_.empty() && ages_.front().frame<cutoff
        ? std::optional<Key>(ages_.front().key) : std::nullopt;
  }
  uint64_t OldestAge(uint64_t frame) const {
    return ages_.empty()?0:frame-ages_.front().frame;
  }
  // Remove only this key's associations, never scan unrelated entries.
  size_t Erase(Key key) {
    auto entry=entries_.find(key);
    if(entry==entries_.end()) return 0;
    const size_t removed=entry->second.aliases.size();
    for(auto alias:entry->second.aliases) aliases_.erase(alias);
    for(auto owner:entry->second.owners) {
      auto reverse=owners_.find(owner);
      reverse->second.erase(key);
      if(reverse->second.empty()) owners_.erase(reverse);
    }
    ages_.erase(entry->second.age);
    entries_.erase(entry);
    return removed;
  }
  size_t Size() const { return entries_.size(); }
  size_t AliasCount() const { return aliases_.size(); }
  // Tests only: exhaustive audit, never invoked from the rendering hot path.
  bool Consistent() const {
    if(ages_.size()!=entries_.size())return false;
    uint64_t prior=0;size_t aliases=0,owners=0,reverseOwners=0;
    for(auto it=ages_.begin();it!=ages_.end();++it) {
      if(it->frame<prior)return false;prior=it->frame;
      auto entry=entries_.find(it->key);
      if(entry==entries_.end() || entry->second.age!=it)return false;
      for(auto a:entry->second.aliases) {
        auto reverse=aliases_.find(a);
        if(reverse==aliases_.end() || reverse->second!=it->key)return false;
        ++aliases;
      }
      for(auto o:entry->second.owners) {
        auto reverse=owners_.find(o);
        if(reverse==owners_.end() || !reverse->second.contains(it->key))return false;
        ++owners;
      }
    }
    for(const auto& [owner,keys]:owners_) {
      if(keys.empty())return false;
      reverseOwners+=keys.size();
    }
    return aliases==aliases_.size() && owners==reverseOwners;
  }
};

struct CacheMaintenanceResult {
  std::array<uint64_t,3> evicted{};
  double milliseconds = 0;
};
// Budget is checked between whole-resource removals. Clock and erase callbacks
// make the production scheduler testable without Metal or wall-clock flakiness.
template<class Clock,class Erase>
CacheMaintenanceResult MaintainResourceCacheIndices(
    const std::array<ResourceCacheIndex*,3>& indices,uint64_t frame,
    unsigned& turn,Clock clock,Erase erase) {
  const uint64_t cutoff=frame>1800?frame-1800:0;
  const double start=clock(),deadline=start+0.0005;
  CacheMaintenanceResult result;
  unsigned empty=0,retired=0;
  for(unsigned attempts=0;attempts<384 && retired<128;++attempts) {
    const unsigned which=turn++%3;
    if(auto key=indices[which]->Expired(cutoff)) {
      erase(which,*key);
      ++result.evicted[which];++retired;empty=0;
    } else if(++empty==3)break;
    if(clock()>=deadline)break;
  }
  result.milliseconds=(clock()-start)*1000;
  return result;
}
} // namespace mcla::metal

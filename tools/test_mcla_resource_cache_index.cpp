#include "../MCLAApp/runtime/MCLAResourceCacheIndex.h"
#include <algorithm>
#include <chrono>
#include <iostream>
#include <map>
#include <random>
#include <set>
#include <vector>
using mcla::metal::ResourceCacheIndex;
struct Ref { uint64_t frame;std::set<uint32_t> owners;std::set<uint64_t> aliases; };
int main() {
  ResourceCacheIndex index;
  std::map<uint64_t,Ref> reference;
  std::map<uint64_t,uint64_t> aliases;
  auto erase=[&](uint64_t key) {
    auto found=reference.find(key);
    if(found==reference.end()){assert(index.Erase(key)==0);return;}
    assert(index.Erase(key)==found->second.aliases.size());
    for(auto alias:found->second.aliases)aliases.erase(alias);
    reference.erase(found);
  };
  std::mt19937 random(823719);
  for(uint64_t frame=0;frame<100000;++frame) {
    uint64_t key=random()%500,alias=random()%1500;
    uint32_t owner=random()%100;
    switch(random()%5) {
      case 0: case 1:
        index.Touch(key,frame);reference[key].frame=frame;
        index.AddOwner(key,owner);reference[key].owners.insert(owner);
        if(auto old=aliases.find(alias);old!=aliases.end())reference.at(old->second).aliases.erase(alias);
        aliases[alias]=key;reference[key].aliases.insert(alias);
        index.BindAlias(key,alias);
        break;
      case 2:erase(key);break;
      case 3: {
        size_t expected=0,actual=0;
        for(const auto& [k,v]:reference)expected+=v.owners.contains(owner);
        while(auto owned=index.FirstOwned(owner)) {
          assert(reference.at(*owned).owners.contains(owner));erase(*owned);++actual;
        }
        assert(actual==expected);break;
      }
      case 4: {
        uint64_t cutoff=frame>250?frame-250:0;
        while(auto expired=index.Expired(cutoff)) {
          assert(reference.at(*expired).frame<cutoff);erase(*expired);
        }
        for(const auto& [k,v]:reference)assert(v.frame>=cutoff);
        break;
      }
    }
    assert(index.Size()==reference.size());assert(index.AliasCount()==aliases.size());
    auto actual=index.FindAlias(alias);auto expected=aliases.find(alias);
    assert(bool(actual)==(expected!=aliases.end()));
    if(actual)assert(*actual==expected->second);
    if(frame%100==0)assert(index.Consistent());
  }
  assert(index.Consistent());
  // Shared ownership/alias rebinding: invalidating either owner must remove
  // all aliases of the old content, but not an alias now bound to new content.
  ResourceCacheIndex shared;
  shared.Touch(0,0);shared.AddOwner(0,0);shared.AddOwner(0,1);
  shared.BindAlias(0,10);shared.BindAlias(0,20);
  shared.Touch(1,1);shared.BindAlias(1,20);
  assert(shared.Erase(*shared.FirstOwned(0))==1);
  assert(!shared.FindAlias(10) && shared.FindAlias(20)==1);
  assert(!shared.FirstOwned(1) && shared.Consistent());
  // Large insertion forces unordered-map rehashes; LRU list iterators survive.
  std::array<ResourceCacheIndex,3> caches;
  for(auto& cache:caches)for(uint64_t k=0;k<20000;++k) {
    cache.Touch(k,0);cache.AddOwner(k,uint32_t(k));cache.BindAlias(k,k);
  }
  for(auto& cache:caches) {cache.Touch(7,1900);assert(cache.Consistent());}
  std::array<ResourceCacheIndex*,3> pointers{&caches[0],&caches[1],&caches[2]};
  unsigned turn=0;
  auto remove=[&](unsigned which,uint64_t key){caches[which].Erase(key);};
  auto result=mcla::metal::MaintainResourceCacheIndices(pointers,1800,turn,[]{return 0.;},remove);
  assert(result.evicted[0]+result.evicted[1]+result.evicted[2]==0); // Strict age cutoff.
  result=mcla::metal::MaintainResourceCacheIndices(pointers,2000,turn,[]{return 0.;},remove);
  assert(result.evicted[0]+result.evicted[1]+result.evicted[2]==128);
  for(auto count:result.evicted)assert(count>=42 && count<=43); // Fairness.
  double time=0;
  result=mcla::metal::MaintainResourceCacheIndices(pointers,2000,turn,[&]{return time;},
      [&](unsigned which,uint64_t key){remove(which,key);time+=.0002;});
  assert(result.evicted[0]+result.evicted[1]+result.evicted[2]==3);
  assert(result.milliseconds>.59 && result.milliseconds<.61); // Stops after indivisible erase.
  // Draining backlog never expires recently touched entries.
  for(unsigned pass=0;pass<500;++pass)
    mcla::metal::MaintainResourceCacheIndices(pointers,2000,turn,[]{return 0.;},remove);
  for(auto& cache:caches)assert(cache.Size()==1 && cache.FindAlias(7)==7 && cache.Consistent());
  std::cout<<"PASS: 100k reference-model operations; owner/alias invalidation, rebinds, rehash, "
              "retention, budget/cap, fairness, and eventual backlog drain\n";
}

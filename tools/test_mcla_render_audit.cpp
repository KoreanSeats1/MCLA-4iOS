#include "../MCLAApp/runtime/MCLAMissingShaderCapture.h"
#include "../MCLAApp/runtime/MCLAApplicationActivity.h"
#include <cassert>
#include <chrono>
#include <cstdio>
#include <future>

int main() {
  mcla::native::MissingShaderCaptureBudget budget;
  for (unsigned i=0;i<64;++i) {
    assert(budget.Take(i+1,100));
    for (unsigned draw=0;draw<1000;++draw) assert(!budget.Take(i+1,100));
  }
  assert(!budget.Take(1000,2000));
  mcla::native::MissingShaderCaptureBudget stagePairs;
  assert(stagePairs.Take(10,20));assert(stagePairs.Take(20,10));
  mcla::metal::ApplicationActivity activity;
  assert(activity.Wait(false));
  for (unsigned cycle=0;cycle<10;++cycle) {
    activity.Set(false);assert(!activity.IsActive());assert(!activity.Wait(false));
    auto waiter=std::async(std::launch::async,[&]{return activity.Wait();});
    assert(waiter.wait_for(std::chrono::milliseconds(10))==std::future_status::timeout);
    activity.Set(true);
    assert(waiter.wait_for(std::chrono::seconds(5))==std::future_status::ready);
    assert(waiter.get());assert(activity.IsActive());
  }
  puts("64,000 duplicate missing-shader draws bounded; stage pairs and 10 background/resume cycles passed");
}

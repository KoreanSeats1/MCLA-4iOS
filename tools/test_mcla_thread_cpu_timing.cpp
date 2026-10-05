#include "../MCLAApp/runtime/MCLAThreadCPUTiming.h"
#include <cassert>
#include <chrono>
#include <cstdio>
#include <thread>

static double WallSeconds() {
  using namespace std::chrono;
  return duration<double>(steady_clock::now().time_since_epoch()).count();
}

int main() {
  auto before=mcla::metal::TakeThreadCPUSample(WallSeconds());
  std::this_thread::sleep_for(std::chrono::milliseconds(30));
  auto after=mcla::metal::TakeThreadCPUSample(WallSeconds());
  auto idle=mcla::metal::MeasureThreadCPUInterval(before,after);
  assert(idle.valid && idle.wallMilliseconds>=25);
  assert(idle.cpuMilliseconds<idle.wallMilliseconds*.5f);
  before=mcla::metal::TakeThreadCPUSample(WallSeconds());
  volatile unsigned accumulator=0;
  for(unsigned i=0;i<30000000;++i)accumulator=accumulator+i;
  after=mcla::metal::TakeThreadCPUSample(WallSeconds());
  auto active=mcla::metal::MeasureThreadCPUInterval(before,after);
  assert(active.valid && active.cpuMilliseconds>2);
  assert(active.cpuMilliseconds<=active.wallMilliseconds+1);
  mcla::metal::ThreadCPUSample other{};
  std::thread worker([&] {other=mcla::metal::TakeThreadCPUSample(WallSeconds());});
  worker.join();
  assert(!mcla::metal::MeasureThreadCPUInterval(before,other).valid);
  std::printf("thread CPU clock: sleep wall %.2f CPU %.2f ms; busy wall %.2f CPU %.2f ms; thread mismatch rejected\n",
      idle.wallMilliseconds,idle.cpuMilliseconds,
      active.wallMilliseconds,active.cpuMilliseconds);
}

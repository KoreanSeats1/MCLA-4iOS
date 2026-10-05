#pragma once

#include <cstdint>
#include <pthread.h>
#include <time.h>

namespace mcla::metal {

// Thread CPU time excludes time asleep or descheduled. Read only during a
// bounded performance capture; normal gameplay avoids this clock entirely.
inline uint64_t ThreadCPUTimeNanoseconds() {
  timespec now{};
  if (clock_gettime(CLOCK_THREAD_CPUTIME_ID, &now) != 0) return 0;
  return uint64_t(now.tv_sec) * 1000000000ull + uint64_t(now.tv_nsec);
}

struct ThreadCPUSample {
  double wallSeconds = 0;
  uint64_t cpuNanoseconds = 0;
  pthread_t thread{};
};

inline ThreadCPUSample TakeThreadCPUSample(double wallSeconds) {
  return {wallSeconds, ThreadCPUTimeNanoseconds(), pthread_self()};
}

struct ThreadCPUInterval {
  float wallMilliseconds = -1;
  float cpuMilliseconds = -1;
  bool valid = false;
};

inline ThreadCPUInterval MeasureThreadCPUInterval(
    const ThreadCPUSample& begin, const ThreadCPUSample& end) {
  if (!begin.cpuNanoseconds || !end.cpuNanoseconds ||
      !pthread_equal(begin.thread, end.thread) ||
      end.cpuNanoseconds < begin.cpuNanoseconds ||
      end.wallSeconds < begin.wallSeconds) return {};
  return {float((end.wallSeconds - begin.wallSeconds) * 1000.0),
          float((end.cpuNanoseconds - begin.cpuNanoseconds) / 1000000.0), true};
}

} // namespace mcla::metal

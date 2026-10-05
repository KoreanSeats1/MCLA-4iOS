// Host-only generated fixtures for decode_mcla_metal_frame. Pass the built
// decoder executable as argv[1]. No device, screenshots, or game data required.
#define STB_IMAGE_IMPLEMENTATION
#include <stb_image.h>
#include <array>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <limits>
#include <spawn.h>
#include <string>
#include <sys/wait.h>
#include <unistd.h>
#include <vector>
extern char **environ;

static void Require(bool ok, const char *what) {
  if (!ok) { std::fprintf(stderr, "FAIL: %s\n", what); std::exit(1); }
}
static std::string Run(const char *decoder, const std::string &input,
                       const std::string &output, bool depth) {
  std::vector<char *> args{const_cast<char *>(decoder),
      const_cast<char *>(input.c_str()), const_cast<char *>("2"),
      const_cast<char *>("3"), const_cast<char *>(output.c_str())};
  if (depth) args.push_back(const_cast<char *>("r32f"));
  args.push_back(nullptr);
  int descriptors[2];
  Require(pipe(descriptors) == 0, "create stdout pipe");
  posix_spawn_file_actions_t actions;
  posix_spawn_file_actions_init(&actions);
  posix_spawn_file_actions_adddup2(&actions, descriptors[1], STDOUT_FILENO);
  posix_spawn_file_actions_addclose(&actions, descriptors[0]);
  posix_spawn_file_actions_addclose(&actions, descriptors[1]);
  pid_t pid;
  Require(posix_spawn(&pid, decoder, &actions, nullptr, args.data(), environ) == 0,
          "start decoder");
  posix_spawn_file_actions_destroy(&actions);
  close(descriptors[1]);
  std::string result;
  std::array<char, 1024> buffer{};
  ssize_t count;
  while ((count = read(descriptors[0], buffer.data(), buffer.size())) > 0)
    result.append(buffer.data(), size_t(count));
  close(descriptors[0]);
  int status;
  Require(waitpid(pid, &status, 0) == pid && WIFEXITED(status) &&
          WEXITSTATUS(status) == 0, "decoder succeeded");
  return result;
}
template <class T, size_t N>
static void Write(const std::string &path, const std::array<T, N> &values) {
  std::ofstream stream(path, std::ios::binary);
  stream.write(reinterpret_cast<const char *>(values.data()), sizeof(values));
  Require(bool(stream), "write generated fixture");
}
static void Check(const std::string &path,
                  const std::array<uint8_t, 24> &expected) {
  int w = 0, h = 0, channels = 0;
  auto *actual = stbi_load(path.c_str(), &w, &h, &channels, 4);
  Require(actual && w == 2 && h == 3, "read decoded 2x3 PNG");
  for (unsigned i = 0; i < expected.size(); ++i) {
    if (actual[i] != expected[i]) {
      std::fprintf(stderr, "%s component=%u actual=%u expected=%u\n",
                   path.c_str(), i, actual[i], expected[i]);
      Require(false, "exact decoded pixel");
    }
  }
  stbi_image_free(actual);
}
int main(int argc, char **argv) {
  Require(argc == 2, "usage: test_decode_mcla_metal_frame decoder-path");
  char pattern[] = "/tmp/mcla-depth-decode-test-XXXXXX";
  const char *directory = mkdtemp(pattern);
  Require(directory != nullptr, "create fixture directory");
  const std::string base(directory), input = base + "/input.bin",
                    output = base + "/output.png";
  std::array<float, 6> depth{-.25f, 0.f, .5f, 1.f, 1.25f,
                            std::numeric_limits<float>::quiet_NaN()};
  Write(input, depth);
  auto report = Run(argv[1], input, output, true);
  Require(report.find("nonfinite=1") != std::string::npos &&
          report.find("min=-0.25 max=1.25") != std::string::npos,
          "raw finite depth range and nonfinite report");
  Check(output, {0,0,0,255, 0,0,0,255, 128,128,128,255,
                 255,255,255,255, 255,255,255,255, 0,0,0,255});
  std::printf("%s", report.c_str());
  depth.fill(std::numeric_limits<float>::infinity());
  Write(input, depth);
  report = Run(argv[1], input, output, true);
  Require(report.find("nonfinite=6") != std::string::npos &&
          report.find("min=none max=none") != std::string::npos,
          "all-nonfinite range handling");
  std::printf("%s", report.c_str());

  const std::array<uint8_t, 24> rgba{
      0,1,2,3, 32,64,96,128, 255,254,253,252,
      5,9,13,17, 120,121,122,123, 0,0,0,0};
  Write(input, rgba);
  report = Run(argv[1], input, output, false);
  auto opaque = rgba;
  for (unsigned p = 0; p < 6; ++p) opaque[p * 4 + 3] = 255;
  Check(output, opaque);
  Require(report.find("half=0") != std::string::npos, "RGBA8 auto-detection");
  std::array<_Float16, 24> half{};
  for (unsigned p = 0; p < 6; ++p) {
    half[p * 4] = 0.f; half[p * 4 + 1] = .5f;
    half[p * 4 + 2] = 1.f; half[p * 4 + 3] = .25f;
    opaque[p * 4] = 0; opaque[p * 4 + 1] = 128;
    opaque[p * 4 + 2] = 255; opaque[p * 4 + 3] = 255;
  }
  Write(input, half);
  report = Run(argv[1], input, output, false);
  Check(output, opaque);
  Require(report.find("half=1") != std::string::npos, "RGBA16F auto-detection");
  std::printf("PASS: R32F grayscale/range/nonfinite, RGBA8 and RGBA16F fixtures (%s)\n",
               directory);
}

// Renders 360 Reality Audio to headphone binaural stereo with QQ Music's Sony decoder.
// The decoder exports C++ members only, resolved here by their mangled names; on arm64 a
// member function takes `this` as its first argument.
#include <dlfcn.h>
#include <sys/stat.h>

#include <cstdint>
#include <cstdio>
#include <string>
#include <vector>

using PcmCallback = bool (*)(void* user, const std::uint8_t* pcm, std::size_t length);

extern "C" const unsigned char kanade_ra360_hrtf[];

namespace {
constexpr char hrtf_name[] = "com.sony.360ra.hrtf13.standard.hki";
constexpr char config_name[] = "com.sony.360ra.hrtf13.config";
// The config names the coefficient file on its first line.
constexpr char config[] = "com.sony.360ra.hrtf13.standard.hki\n";

struct Runtime {
  // FileDataSource(char const*, int), open(), ~FileDataSource().
  void (*source_create)(void* self, const char* path, int copy_for_debug);
  int (*source_open)(void* self);
  void (*source_destroy)(void* self);
  // The decoder keeps these pointers; they must outlive it.
  void* (*create)(const char* root, const char* coefficients, const char* compensation,
                  const char* speakers);
  int (*init)(void* self, void* source);
  int (*decode)(void* self, unsigned char* buffer, unsigned long offset, unsigned long size);
  long (*min_buffer_size)(void* self);
  int (*release)(void* self);  // Also closes the source, which it does not own.
  void (*destroy)(void* self);
};

template <typename T>
bool resolve(void* library, const char* name, T& function) {
  function = reinterpret_cast<T>(dlsym(library, name));
  return function != nullptr;
}

const Runtime* runtime() {
  static const Runtime* loaded = [] () -> const Runtime* {
    void* library = dlopen("libqm_native_decoder_360ra.so", RTLD_NOW | RTLD_LOCAL);
    if (!library) return nullptr;
    static Runtime value;
    if (resolve(library, "_ZN14FileDataSourceC1EPKci", value.source_create) &&
        resolve(library, "_ZN14FileDataSource4openEv", value.source_open) &&
        resolve(library, "_ZN14FileDataSourceD1Ev", value.source_destroy) &&
        resolve(library, "create_SonyIaNativeDecoder", value.create) &&
        resolve(library, "_ZN19SonyIaNativeDecoder4initEP11IDataSource", value.init) &&
        resolve(library, "_ZN19SonyIaNativeDecoder6decodeEPhmm", value.decode) &&
        resolve(library, "_ZN19SonyIaNativeDecoder16getMinBufferSizeEv", value.min_buffer_size) &&
        resolve(library, "_ZN19SonyIaNativeDecoder7releaseEv", value.release) &&
        resolve(library, "destroy_SonyIaNativeDecoder", value.destroy)) {
      return &value;
    }
    dlclose(library);
    return nullptr;
  }();
  return loaded;
}

bool write_file(const std::string& path, const void* data, std::size_t size) {
  struct stat info {};
  if (stat(path.c_str(), &info) == 0 && static_cast<std::size_t>(info.st_size) == size) return true;
  const std::string temp = path + ".tmp";
  std::FILE* file = std::fopen(temp.c_str(), "wb");
  if (!file) return false;
  const bool written = std::fwrite(data, 1, size, file) == size;
  return std::fclose(file) == 0 && written && std::rename(temp.c_str(), path.c_str()) == 0;
}
}  // namespace

extern "C" __attribute__((visibility("default"))) bool kanade_ra360_available() {
  return runtime() != nullptr;
}

// Writes 48 kHz stereo 32-bit PCM to `on_pcm`. Returns 0 when done, 1 when `on_pcm` stopped
// the decode, 2 when the work directory is unusable, 3 when the decoder rejected the file,
// 4 on a decode error and 5 when the decoder is missing; `detail` receives its own code.
extern "C" __attribute__((visibility("default"))) int kanade_ra360_decode(
    const char* input, const char* work_dir, PcmCallback on_pcm, void* user, int* detail) {
  *detail = 0;
  const Runtime* api = runtime();
  if (!api) return 5;
  const std::string root = work_dir;
  if (!write_file(root + "/" + hrtf_name, kanade_ra360_hrtf, KANADE_RA360_HRTF_SIZE) ||
      !write_file(root + "/" + config_name, config, sizeof(config) - 1)) {
    return 2;
  }
  // The headphone compensation file is optional and left out.
  void* decoder = api->create(root.c_str(), config_name, "none.config", nullptr);
  if (!decoder) return 3;

  alignas(8) unsigned char source[0x40];
  api->source_create(source, input, 0);
  api->source_open(source);  // init() only seeks and sizes the source.
  int status = 0;
  *detail = api->init(decoder, source);
  if (*detail != 0) {
    status = 3;
  } else {
    const long size = api->min_buffer_size(decoder);
    std::vector<unsigned char> buffer(size > 0 ? static_cast<std::size_t>(size) : 0x2000);
    for (;;) {
      const int written = api->decode(decoder, buffer.data(), 0, buffer.size());
      if (written < 0) {
        *detail = written;
        status = 4;
        break;
      }
      if (written == 0) break;
      if (!on_pcm(user, buffer.data(), static_cast<std::size_t>(written))) {
        status = 1;
        break;
      }
    }
    api->release(decoder);
  }
  api->destroy(decoder);
  api->source_destroy(source);
  return status;
}

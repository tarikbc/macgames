// prepare-pipelines.exe <recipe folder> <shader cache folder>
//
// Overwatch's DXMT build records each graphics pipeline the game creates as a recipe
// in DXMT_OWT_RECIPE_DIR. Before the next launch this tool builds every recipe again
// into a Metal binary archive in DXMT_OWT_PIPELINE_CACHE, so the game finds its
// pipelines ready instead of compiling them in the middle of a match. The archive
// format and file names come from DXMT's own code (MIT, from the overwatch pack's
// Sources), so the game reads what this tool writes. Shaders come from the cache DXMT
// keeps in <shader cache folder>. Folders are Mac paths. DXMT accepts the archive
// folder only in a program named prepare-pipelines, so keep this file name.
//
// Output: one JSON object per line. Exit codes: 0 all recipes prepared, 1 some failed,
// 2 usage, 3 no Metal device, 4 more recipes than the archive store accepts.
#include "owt_recipe.hpp"
#include <algorithm>
#include <map>
#include <vector>

using namespace dxmt;
namespace dxmt { Logger Logger::s_instance("prepare-pipelines.log"); }

// The version DXMT writes into its shader cache (kDXMTShaderCacheVersion).
constexpr uint64_t ShaderCacheVersion = 18;

static std::string utf8(const wchar_t *text) {
  int n = WideCharToMultiByte(CP_UTF8, 0, text, -1, nullptr, 0, nullptr, nullptr);
  if (n <= 1) return {};
  std::string out(size_t(n - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, text, -1, out.data(), n, nullptr, nullptr);
  return out;
}

// Recipe file names in `folder`, sorted so runs are repeatable.
static std::vector<std::string> recipes(const std::string &folder) {
  std::vector<std::string> names;
  WIN32_FIND_DATAW found{};
  HANDLE search = FindFirstFileW(owtarchive::winpath(folder + "/*.recipe").c_str(), &found);
  if (search == INVALID_HANDLE_VALUE) return names;
  do {
    if (!(found.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) names.push_back(utf8(found.cFileName));
  } while (names.size() <= owtarchive::MaxFiles && FindNextFileW(search, &found));
  FindClose(search);
  std::sort(names.begin(), names.end());
  return names;
}

// Reads a recipe and checks that it is whole: its name is the SHA-1 of its bytes.
static bool read(const std::string &folder, const std::string &name, owtrecipe::Recipe &recipe) {
  HANDLE file = CreateFileW(owtarchive::winpath(folder + "/" + name).c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
                            OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  DWORD got = 0;
  LARGE_INTEGER size{};
  bool ok = GetFileSizeEx(file, &size) && size.QuadPart == sizeof recipe &&
            ReadFile(file, &recipe, sizeof recipe, &got, nullptr) && got == sizeof recipe;
  CloseHandle(file);
  return ok && !memcmp(recipe.magic, "OWTRCP01", 8) && recipe.version == 1 && recipe.info_size == sizeof recipe.info &&
         Sha1HashState::compute(&recipe, sizeof recipe).string() + ".recipe" == name;
}

// Builds one shader function from the bytecode DXMT cached for it.
static WMT::Reference<WMT::Function> function(WMT::Device device, const owtrecipe::Ingredient &shader, const std::string &cache) {
  if (!memchr(shader.function, 0, sizeof shader.function) || !shader.function[0]) return {};
  auto db = cache + "/shaders_" + std::to_string(shader.metal_version) + ".db";
  auto reader = WMT::CacheReader::alloc_init(db.c_str(), ShaderCacheVersion);
  if (!reader) return {};
  auto bytecode = reader.get(std::make_pair(shader.source, shader.variant));
  if (!bytecode) return {};
  WMT::Reference<WMT::Error> error;
  auto library = device.newLibrary(bytecode, error);
  if (!library || error) return {};
  return library.newFunction(shader.function);
}

// Builds and stores the archive of one recipe, then loads it back to prove the game can use it.
// Returns nullptr on success, else a fixed reason that holds no shader data.
static const char *prepare(WMT::Device device, const owtrecipe::Recipe &recipe, const std::string &cache, bool &cached) {
  auto vertex = function(device, recipe.vertex, cache);
  auto fragment = function(device, recipe.pixel, cache);
  if (!vertex || (recipe.pixel.function[0] && !fragment)) return "shader-load";
  WMTRenderPipelineInfo info = recipe.info;
  info.vertex_function = vertex.handle;
  info.fragment_function = fragment ? fragment.handle : 0;
  info.binary_archive_for_serialization = 0;
  info.binary_archives_for_lookup.set(nullptr);
  info.num_binary_archives_for_lookup = 0;
  info.fail_on_binary_archive_miss = false;

  auto path = owtarchive::store().directory + "/" +
              owtarchive::key(device, info, recipe.vertex.cache_key, recipe.pixel.cache_key).string() + ".metalarc";
  bool existed = owtarchive::size(owtarchive::winpath(path)) > 0;
  WMT::Reference<WMT::Error> error;
  owtarchive::Pending pending;
  auto pipeline = owtarchive::create(device, info, recipe.vertex.cache_key, recipe.pixel.cache_key, error, pending, 0);
  if (!pipeline || error) return "pipeline-create";
  cached = existed && !pending.archive;
  pending.save();
  if (!owtarchive::size(owtarchive::winpath(path))) return "archive-not-saved";

  WMT::Reference<WMT::Error> loadError;
  auto archive = device.newBinaryArchive(path.c_str(), loadError);
  if (!archive || loadError) return "archive-load";
  obj_handle_t handle = archive.handle;
  info.binary_archives_for_lookup.set(&handle);
  info.num_binary_archives_for_lookup = 1;
  info.fail_on_binary_archive_miss = true;
  WMT::Reference<WMT::Error> checkError;
  auto check = device.newRenderPipelineState(info, checkError);
  return check && !checkError ? nullptr : "archive-verification";
}

int wmain(int argc, wchar_t **argv) {
  if (argc != 3) return 2;
  std::string folder = utf8(argv[1]), cache = utf8(argv[2]);
  if (owtarchive::store().directory.empty()) {
    std::printf("{\"stage\":\"failure\",\"reason\":\"no-archive-folder\"}\n");
    return 2;
  }
  auto devices = WMT::CopyAllDevices();
  if (!devices.count()) return 3;
  auto device = devices.object(0);
  auto names = recipes(folder);
  if (names.size() > owtarchive::MaxFiles) return 4;

  unsigned done = 0, cached = 0, failed = 0;
  std::map<std::string, unsigned> reasons;
  for (auto &name : names) {
    auto pool = WMT::MakeAutoreleasePool();
    owtrecipe::Recipe recipe{};
    bool hit = false;
    const char *reason = read(folder, name, recipe) ? prepare(device, recipe, cache, hit) : "invalid-recipe";
    if (reason) { failed++; reasons[reason]++; }
    else { done++; cached += hit; }
    std::printf("{\"stage\":\"preparing\",\"done\":%u,\"failed\":%u,\"cached\":%u,\"total\":%zu}\n", done, failed, cached, names.size());
    std::fflush(stdout);
  }
  for (auto &[reason, count] : reasons) std::printf("{\"stage\":\"failures\",\"reason\":\"%s\",\"count\":%u}\n", reason.c_str(), count);
  std::printf("{\"stage\":\"complete\",\"done\":%u,\"failed\":%u,\"cached\":%u,\"total\":%zu}\n", done, failed, cached, names.size());
  std::fflush(stdout);
  return failed ? 1 : 0;
}

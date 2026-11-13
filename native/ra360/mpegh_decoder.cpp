// Renders an MPEG-H 3D Audio MHAS stream to packed 24-bit speaker PCM.
// Kept apart from speaker_layout.cpp: libmpegh's VOID typedef clashes with windows.h.
#include <cstdint>
#include <cstdlib>
#include <cstring>

extern "C" {
#include "impeghd_type_def.h"
#include "impeghd_config_params.h"
#include "impeghd_error_codes.h"
#include "impeghd_memory_standards.h"
}
#include "impeghd_api.h"

using PcmCallback = bool (*)(void* user, const std::uint8_t* pcm, std::size_t length);

namespace {
pVOID allocate(UWORD32 size, UWORD32 alignment) { return std::malloc(size + alignment); }

struct Decoder {
  ia_mpeghd_api_struct api{};
  bool created = false;

  ~Decoder() {
    if (created) ia_mpegh_dec_delete(&api.output_config);
  }
};

// Moves unconsumed bytes to the front and tops the input buffer up from the stream.
void refill(ia_output_config& out, std::uint8_t* buffer, WORD32& filled, const std::uint8_t* data,
            std::size_t length, std::size_t& offset) {
  const WORD32 left = filled - out.i_bytes_consumed;
  std::memmove(buffer, buffer + out.i_bytes_consumed, left);
  const std::size_t room = out.ui_inp_buf_size - left;
  const std::size_t count = room < length - offset ? room : length - offset;
  std::memcpy(buffer + left, data + offset, count);
  offset += count;
  filled = left + static_cast<WORD32>(count);
  out.i_bytes_consumed = 0;
}
}  // namespace

// Returns 0 when done, 1 when `on_pcm` stopped the decode, and an error code otherwise.
extern "C" __declspec(dllexport) int kanade_ra360_decode(const std::uint8_t* data, std::size_t length,
                                                         int cicp_layout, PcmCallback on_pcm,
                                                         void* user) {
  Decoder decoder;
  ia_input_config& in = decoder.api.input_config;
  ia_output_config& out = decoder.api.output_config;
  in.ui_pcm_wd_sz = 24;
  in.ui_mhas_flag = IMPEGHD_CONFIG_PARAM_MHAS_FLAG_DFLT_VAL;
  in.ui_cicp_layout_idx = cicp_layout;
  in.i_preset_id = IMPEGHD_CONFIG_PARAM_PRESET_ID_DFLT_VAL;
  out.malloc_mpegh = allocate;
  out.free_mpegh = std::free;
  IA_ERRORCODE code = ia_mpegh_dec_create(&in, &out);
  if (code != IA_MPEGH_DEC_NO_ERROR) return code < 0 ? code : -1;
  decoder.created = true;

  auto* input = static_cast<std::uint8_t*>(out.mem_info_table[IA_MEMTYPE_INPUT].mem_ptr);
  auto* output = static_cast<std::uint8_t*>(out.mem_info_table[IA_MEMTYPE_OUTPUT].mem_ptr);
  std::size_t offset = 0;
  WORD32 filled = 0;
  out.i_bytes_consumed = 0;
  do {
    refill(out, input, filled, data, length, offset);
    if (filled <= 0) return -2;
    in.num_inp_bytes = filled;
    code = ia_mpegh_dec_init(out.pv_ia_process_api_obj, &in, &out);
    if (code < 0) return code;
    if (!out.ui_init_done && out.i_bytes_consumed == 0 && offset == length) return -2;
  } while (!out.ui_init_done);
  if (out.i_num_chan != cicp_layout || out.i_pcm_wd_sz != 24 || out.i_samp_freq != 48000) {
    return -4;  // CICP 2 and 6 have 2 and 6 channels.
  }
  // Like the reference testbench, a non-fatal init error mutes the stream.
  const bool muted = code != IA_MPEGH_DEC_NO_ERROR;

  for (;;) {
    refill(out, input, filled, data, length, offset);
    if (filled <= 0) return 0;
    in.num_inp_bytes = filled;
    code = ia_mpegh_dec_execute(out.pv_ia_process_api_obj, &in, &out);
    if (code < 0) return code;
    if (out.num_out_bytes > 0) {
      if (muted) std::memset(output, 0, out.num_out_bytes);
      if (!on_pcm(user, output, static_cast<std::size_t>(out.num_out_bytes))) return 1;
    } else if (out.i_bytes_consumed == 0) {
      // Nothing moved with a full buffer: trailing bytes at the end, a stuck stream otherwise.
      return offset == length ? 0 : -3;
    }
  }
}

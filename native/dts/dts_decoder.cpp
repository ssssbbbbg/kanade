#include <cstdint>

extern "C" {
int DTSPlayback_InitialiseDTS(void**);
int DTSPlayback_InstallLicense(void*, const void*, int);
int DTSPlayback_LoadConfiguration(void*, const void*, int, const char**);
int DTSPlayback_SetOutputChannelLayout(void*, int);
int DTSPlayback_DecodeDTS(void*, const void*, int, int*, int*, int*, float***);
void DTSPlayback_Release(void**);

extern const std::uint8_t kanade_dts_config[];
extern const std::uint8_t kanade_dts_license[];
}

struct PcmFrame {
    const float* left;
    const float* right;
    int frames;
};

extern "C" void* kanade_dts_create() {
    void* decoder = nullptr;
    if (DTSPlayback_InitialiseDTS(&decoder) != 0 || !decoder) {
        if (decoder) DTSPlayback_Release(&decoder);
        return nullptr;
    }
    const char* config_error = nullptr;
    constexpr int stereo_layout = 1;
    if (DTSPlayback_InstallLicense(decoder, kanade_dts_license, DTS_LICENSE_SIZE) != 0 ||
        DTSPlayback_LoadConfiguration(decoder, kanade_dts_config, DTS_CONFIG_SIZE, &config_error) != 0 ||
        DTSPlayback_SetOutputChannelLayout(decoder, stereo_layout) != 0) {
        DTSPlayback_Release(&decoder);
        return nullptr;
    }
    return decoder;
}

extern "C" int kanade_dts_frame(void* decoder, const std::uint8_t* data, int length, PcmFrame* pcm) {
    int layout = 0, channels = 0, frames = 0;
    float** planes = nullptr;
    const int result = DTSPlayback_DecodeDTS(decoder, data, length, &layout, &channels, &frames, &planes);
    if (result != 0) return result;
    if (channels != 2 || frames <= 0 || frames > 8192 || !planes || !planes[0] || !planes[1]) return -1;
    *pcm = {planes[0], planes[1], frames};
    return 0;
}

extern "C" void kanade_dts_destroy(void* decoder) {
    DTSPlayback_Release(&decoder);
}

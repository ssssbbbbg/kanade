#include <MNN/Interpreter.hpp>
#include <MNN/Tensor.hpp>

#include <algorithm>
#include <array>
#include <cmath>
#include <complex>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <limits>
#include <memory>
#include <string>
#include <vector>

#ifdef _WIN32
#include <windows.h>
#undef NO_ERROR
extern "C" IMAGE_DOS_HEADER __ImageBase;
using PathChar = wchar_t;
#define NAC_EXPORT __declspec(dllexport)
#else
extern "C" const uint8_t kanade_nac_model[];
using PathChar = char;
#define NAC_EXPORT
#endif

namespace {
constexpr int channels = 2;
constexpr int frames = 32;
constexpr int codebooks = 22;
constexpr int fft_size = 512;
constexpr int hop = fft_size / 2;
constexpr int bins = hop + 1;
constexpr int segment_bytes = 1764;
constexpr int model_frames = frames + 2;
constexpr float pi = 3.14159265358979323846f;
constexpr auto max_wave_samples =
    (std::numeric_limits<uint32_t>::max() - 36) / (channels * sizeof(int16_t));

const void* model_data() {
#ifdef _WIN32
    const auto module = reinterpret_cast<HMODULE>(&__ImageBase);
    const auto resource = FindResourceW(module, MAKEINTRESOURCEW(1), MAKEINTRESOURCEW(10));
    return resource ? LockResource(LoadResource(module, resource)) : nullptr;
#else
    return kanade_nac_model;
#endif
}

class WaveWriter {
public:
    WaveWriter(const PathChar* path, int rate, uint32_t samples)
        : output_(std::filesystem::path(path), std::ios::binary) {
        const uint32_t data_bytes = samples * channels * sizeof(int16_t);
        output_.write("RIFF", 4);
        write_number<uint32_t>(36 + data_bytes);
        output_.write("WAVEfmt ", 8);
        write_number<uint32_t>(16);
        write_number<uint16_t>(1);
        write_number<uint16_t>(channels);
        write_number<uint32_t>(rate);
        write_number<uint32_t>(rate * channels * sizeof(int16_t));
        write_number<uint16_t>(channels * sizeof(int16_t));
        write_number<uint16_t>(16);
        output_.write("data", 4);
        write_number(data_bytes);
    }

    bool append(const std::array<int16_t, hop * channels>& samples) {
        output_.write(reinterpret_cast<const char*>(samples.data()), sizeof(samples));
        written_ += sizeof(samples);
        return static_cast<bool>(output_);
    }

    bool flush() {
        output_.flush();
        return static_cast<bool>(output_);
    }

    uint64_t written() const { return written_; }

    bool finish() {
        output_.close();
        return static_cast<bool>(output_);
    }

private:
    template <typename T>
    void write_number(T value) {
        output_.write(reinterpret_cast<const char*>(&value), sizeof(value));
    }

    std::ofstream output_;
    uint64_t written_ = 44;
};

class Synthesizer {
public:
    Synthesizer() {
        for (int i = 0; i < fft_size; ++i) {
            const float angle = 2 * pi * i / fft_size;
            window_[i] = (1 - std::cos(angle)) / 2;
            phase_[i] = std::polar(1.0f, angle);
        }
    }

    bool append(const float* spectrum, WaveWriter& output) {
        std::array<int16_t, hop * channels> block;
        for (int frame = 1; frame <= frames; ++frame) {
            for (int ch = 0; ch < channels; ++ch) {
                const auto* real = spectrum + (ch * 2 * model_frames + frame) * bins;
                const auto* imag = real + model_frames * bins;
                std::array<std::complex<float>, fft_size> wave;
                for (int bin = 0; bin < bins; ++bin) {
                    wave[bin] = {real[bin], imag[bin]};
                }
                for (int bin = 1; bin < hop; ++bin) {
                    wave[fft_size - bin] = std::conj(wave[bin]);
                }
                inverse_fft(wave);
                for (int i = 0; i < hop; ++i) {
                    const float left = window_[i], right = window_[i + hop];
                    const float weight = left * left + (started_ ? right * right : 0);
                    const float sample = wave[i].real() * left / fft_size + overlap_[ch][i];
                    block[i * channels + ch] = quantize(weight > 1e-6f ? sample / weight : 0);
                    overlap_[ch][i] = wave[i + hop].real() * right / fft_size;
                }
            }
            started_ = true;
            if (!output.append(block)) return false;
        }
        return true;
    }

    bool finish(WaveWriter& output) {
        std::array<int16_t, hop * channels> tail;
        for (int i = 0; i < hop; ++i) {
            const float w = window_[i + hop];
            for (int ch = 0; ch < channels; ++ch) {
                tail[i * channels + ch] = quantize(w * w > 1e-6f ? overlap_[ch][i] / (w * w) : 0);
            }
        }
        return output.append(tail) && output.finish();
    }

private:
    static int16_t quantize(float sample) {
        return std::isfinite(sample) ? static_cast<int16_t>(
            std::lround(std::clamp(sample, -1.0f, 1.0f) * 32767)) : 0;
    }

    void inverse_fft(std::array<std::complex<float>, fft_size>& wave) const {
        for (int i = 1, j = 0; i < fft_size; ++i) {
            int bit = fft_size / 2;
            while (j & bit) {
                j ^= bit;
                bit >>= 1;
            }
            j ^= bit;
            if (i < j) std::swap(wave[i], wave[j]);
        }
        for (int width = 2; width <= fft_size; width *= 2) {
            for (int start = 0; start < fft_size; start += width) {
                for (int i = 0; i < width / 2; ++i) {
                    auto& low = wave[start + i];
                    auto& high = wave[start + i + width / 2];
                    const auto rotated = high * phase_[i * fft_size / width];
                    high = low - rotated;
                    low += rotated;
                }
            }
        }
    }

    std::array<float, fft_size> window_;
    std::array<std::complex<float>, fft_size> phase_;
    std::array<std::array<float, hop>, channels> overlap_{};
    bool started_ = false;
};

void read_codes(const uint8_t* data, int32_t* codes) {
    int index = 0;
    for (int ch = 0; ch < channels; ++ch) {
        for (int frame = 0; frame < frames; ++frame) {
            for (int book = 0; book < codebooks; ++book, ++index) {
                const int bit = index * 10;
                const int byte = bit / 8;
                const int word = data[byte] | (data[byte + 1] << 8);
                codes[(ch * codebooks + book) * frames + frame] = (word >> (bit % 8)) & 1023;
            }
        }
    }
}

struct Feedback {
    MNN::Tensor* input;
    MNN::Tensor* output;
    std::unique_ptr<MNN::Tensor> host;
};
} // namespace

// 每次解码独立创建模型会话。每解完一段就把已写入的字节数交给 progress，
// 播放器可以边解边读；progress 返回 false 时取消（切歌）。
extern "C" NAC_EXPORT int kanade_nac_decode(
    const uint8_t* payload, size_t segments, int rate, const PathChar* path,
    bool (*progress)(const void*, uint64_t), const void* user
) {
    if (segments == 0 || segments > (max_wave_samples - hop) / (frames * hop)) return 6;
    const auto* model = model_data();
    if (!model) return 1;
    std::unique_ptr<MNN::Interpreter> engine(
        MNN::Interpreter::createFromBuffer(model, KANADE_NAC_MODEL_SIZE));
    if (!engine) return 1;
    MNN::ScheduleConfig config;
    config.type = MNN_FORWARD_CPU;
    config.numThread = 2;
    auto* session = engine->createSession(config);
    if (!session) return 2;
    auto* input = engine->getSessionInput(session, "codes");
    auto* spectrum = engine->getSessionOutput(session, "freq");
    if (!input || !spectrum) return 3;
    MNN::Tensor codes(input, MNN::Tensor::CAFFE);
    MNN::Tensor frequencies(spectrum, MNN::Tensor::CAFFE);
    if (codes.elementSize() != channels * codebooks * frames ||
        frequencies.elementSize() != channels * 2 * model_frames * bins) return 3;
    std::vector<Feedback> feedback;
    for (const char* name : {"buffer_conv_0", "buffer_conv_1", "buffer_conv_2",
                             "buffer_res_0", "buffer_res_1", "buffer_res_2"}) {
        auto* in = engine->getSessionInput(session, name);
        const auto output_name = std::string("out_") + name;
        auto* out = engine->getSessionOutput(session, output_name.c_str());
        if (!in || !out) return 3;
        auto host = std::make_unique<MNN::Tensor>(in, MNN::Tensor::CAFFE);
        std::fill_n(host->host<float>(), host->elementSize(), 0.0f);
        if (!in->copyFromHostTensor(host.get())) return 3;
        feedback.push_back({in, out, std::move(host)});
    }
    WaveWriter wav(path, rate, static_cast<uint32_t>(segments * frames * hop + hop));
    Synthesizer synthesizer;
    for (size_t i = 0; i < segments; ++i) {
        read_codes(payload + i * segment_bytes, codes.host<int32_t>());
        if (!input->copyFromHostTensor(&codes) || engine->runSession(session) != MNN::NO_ERROR ||
            !spectrum->copyToHostTensor(&frequencies)) return 5;
        for (auto& state : feedback) {
            if (!state.output->copyToHostTensor(state.host.get()) ||
                !state.input->copyFromHostTensor(state.host.get())) return 5;
        }
        if (!synthesizer.append(frequencies.host<float>(), wav) || !wav.flush()) return 6;
        if (!progress(user, wav.written())) return 4;
    }
    return synthesizer.finish(wav) ? 0 : 6;
}

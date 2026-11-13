#include <windows.h>
#include <audioclient.h>
#include <mmdeviceapi.h>

// Channel count of the default playback device, or 0 when it cannot be read.
extern "C" __declspec(dllexport) int kanade_ra360_speaker_channels() {
  const HRESULT init = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  int channels = 0;
  IMMDeviceEnumerator* devices = nullptr;
  IMMDevice* device = nullptr;
  IAudioClient* client = nullptr;
  WAVEFORMATEX* format = nullptr;
  if (SUCCEEDED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                                 IID_PPV_ARGS(&devices))) &&
      SUCCEEDED(devices->GetDefaultAudioEndpoint(eRender, eMultimedia, &device)) &&
      SUCCEEDED(device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                                 reinterpret_cast<void**>(&client))) &&
      SUCCEEDED(client->GetMixFormat(&format))) {
    channels = format->nChannels;
  }
  CoTaskMemFree(format);
  if (client) client->Release();
  if (device) device->Release();
  if (devices) devices->Release();
  if (SUCCEEDED(init)) CoUninitialize();
  return channels;
}

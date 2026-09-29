#pragma once
#include <CoreAudio/CoreAudio.h>
#include <stdbool.h>
/// Upper bound for per-app gain. Values above 1.0 pass through a soft limiter.
#define SW_MAX_GAIN 2.0f
typedef struct SWMixer SWMixer;
SWMixer * _Nullable SWMixerCreate(void);
void SWMixerDestroy(SWMixer * _Nonnull mixer);
void SWMixerSetGain(SWMixer * _Nonnull mixer, float gain);
float SWMixerPeak(SWMixer * _Nonnull mixer);
bool SWMixerFormatFailed(SWMixer * _Nonnull mixer);
OSStatus SWMixerRender(AudioObjectID device, const AudioTimeStamp * _Nonnull now,
    const AudioBufferList * _Nonnull input, const AudioTimeStamp * _Nonnull inputTime,
    AudioBufferList * _Nonnull output, const AudioTimeStamp * _Nonnull outputTime, void * _Nullable context);

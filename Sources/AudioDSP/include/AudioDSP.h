#pragma once
#include <CoreAudio/CoreAudio.h>
#include <stdbool.h>
/// Upper bound for per-app gain. Values above 1.0 pass through a soft limiter.
#define SW_MAX_GAIN 2.0f
/// EQ band range in dB (low shelf 100 Hz, peak 1 kHz, high shelf 8 kHz).
#define SW_EQ_RANGE 12.0f
typedef struct SWMixer SWMixer;
SWMixer * _Nullable SWMixerCreate(void);
void SWMixerDestroy(SWMixer * _Nonnull mixer);
void SWMixerSetGain(SWMixer * _Nonnull mixer, float gain);
/// -1 is full left, 0 centered, 1 full right.
void SWMixerSetBalance(SWMixer * _Nonnull mixer, float balance);
void SWMixerSetEQ(SWMixer * _Nonnull mixer, float lowDB, float midDB, float highDB);
void SWMixerSetSampleRate(SWMixer * _Nonnull mixer, double rate);
float SWMixerPeak(SWMixer * _Nonnull mixer);
bool SWMixerFormatFailed(SWMixer * _Nonnull mixer);
OSStatus SWMixerRender(AudioObjectID device, const AudioTimeStamp * _Nonnull now,
    const AudioBufferList * _Nonnull input, const AudioTimeStamp * _Nonnull inputTime,
    AudioBufferList * _Nonnull output, const AudioTimeStamp * _Nonnull outputTime, void * _Nullable context);

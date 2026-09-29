#include "AudioDSP.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

// Only lock-free atomics cross the UI/audio boundary. No allocation, ObjC,
// locks, logging or filesystem access in the real-time callback.
_Static_assert(ATOMIC_INT_LOCK_FREE == 2, "Requires lock-free integer atomics");
struct SWMixer { _Atomic unsigned gainBits, peakBits; _Atomic bool failed; float current; };
static unsigned bits(float f) { unsigned b; memcpy(&b, &f, 4); return b; }
static float value(unsigned b) { float f; memcpy(&f, &b, 4); return f; }
SWMixer *SWMixerCreate(void) {
    SWMixer *m = calloc(1, sizeof(SWMixer));
    if (m) { atomic_init(&m->gainBits, bits(1)); atomic_init(&m->peakBits, bits(0)); atomic_init(&m->failed, false); m->current = 1; }
    return m;
}
void SWMixerDestroy(SWMixer *m) { free(m); }
void SWMixerSetGain(SWMixer *m, float g) {
    if (!isfinite(g)) g = 1;
    atomic_store_explicit(&m->gainBits, bits(fminf(SW_MAX_GAIN, fmaxf(0, g))), memory_order_relaxed);
}
// Boost only: transparent below the knee, then a smooth tanh curve that never exceeds 1.0.
static float limit(float s) {
    const float knee = 0.8f, a = fabsf(s);
    if (a <= knee) return s;
    return copysignf(knee + (1 - knee) * tanhf((a - knee) / (1 - knee)), s);
}
float SWMixerPeak(SWMixer *m) { return value(atomic_exchange_explicit(&m->peakBits, bits(0), memory_order_relaxed)); }
bool SWMixerFormatFailed(SWMixer *m) { return atomic_load_explicit(&m->failed, memory_order_relaxed); }
OSStatus SWMixerRender(AudioObjectID device, const AudioTimeStamp *now,
    const AudioBufferList *input, const AudioTimeStamp *inputTime,
    AudioBufferList *output, const AudioTimeStamp *outputTime, void *context) {
    SWMixer *m = context;
    for (UInt32 b = 0; b < output->mNumberBuffers; b++)
        if (output->mBuffers[b].mData) memset(output->mBuffers[b].mData, 0, output->mBuffers[b].mDataByteSize);
    // Aggregate has no physical input channels: its only input is the stereo tap.
    if (!input->mNumberBuffers || !output->mNumberBuffers) return noErr;
    UInt32 inChannels = 0, outChannels = 0;
    for (UInt32 b = 0; b < input->mNumberBuffers; b++) inChannels += input->mBuffers[b].mNumberChannels;
    for (UInt32 b = 0; b < output->mNumberBuffers; b++) outChannels += output->mBuffers[b].mNumberChannels;
    if (inChannels != 2 || outChannels < 2) { atomic_store(&m->failed, true); return noErr; }
    UInt32 frames = UINT32_MAX;
    for (UInt32 b = 0; b < input->mNumberBuffers; b++) {
        const AudioBuffer *a = &input->mBuffers[b];
        if (!a->mData || !a->mNumberChannels) return noErr;
        UInt32 n = a->mDataByteSize / (sizeof(float) * a->mNumberChannels); if (n < frames) frames = n;
    }
    for (UInt32 b = 0; b < output->mNumberBuffers; b++) {
        const AudioBuffer *a = &output->mBuffers[b];
        if (!a->mData || !a->mNumberChannels) return noErr;
        UInt32 n = a->mDataByteSize / (sizeof(float) * a->mNumberChannels); if (n < frames) frames = n;
    }
    float target = value(atomic_load_explicit(&m->gainBits, memory_order_relaxed)), peak = 0;
    for (UInt32 f = 0; f < frames; f++) {
        m->current += (target - m->current) * 0.002f;
        const bool boosted = m->current > 1.0001f;
        float stereo[2] = {0, 0}; UInt32 channel = 0;
        for (UInt32 b = 0; b < input->mNumberBuffers; b++) {
            const AudioBuffer *a = &input->mBuffers[b]; const float *samples = a->mData;
            for (UInt32 c = 0; c < a->mNumberChannels; c++) {
                float s = samples[f * a->mNumberChannels + c]; if (!isfinite(s)) s = 0;
                s *= m->current; if (boosted) s = limit(s);
                // Peak is measured after gain so meters show what is actually heard.
                peak = fmaxf(peak, fabsf(s)); stereo[channel++] = s;
            }
        }
        channel = 0;
        for (UInt32 b = 0; b < output->mNumberBuffers; b++) {
            AudioBuffer *a = &output->mBuffers[b]; float *samples = a->mData;
            for (UInt32 c = 0; c < a->mNumberChannels; c++, channel++)
                if (channel < 2) samples[f * a->mNumberChannels + c] = stereo[channel];
        }
    }
    unsigned old = atomic_load_explicit(&m->peakBits, memory_order_relaxed);
    while (value(old) < peak && !atomic_compare_exchange_weak_explicit(&m->peakBits, &old, bits(peak), memory_order_relaxed, memory_order_relaxed)) {}
    return noErr;
}

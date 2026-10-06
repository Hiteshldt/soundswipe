#include "AudioDSP.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

// Only lock-free atomics cross the UI/audio boundary. No allocation, ObjC,
// locks, logging or filesystem access in the real-time callback.
_Static_assert(ATOMIC_INT_LOCK_FREE == 2, "Requires lock-free integer atomics");
typedef struct { double b0, b1, b2, a1, a2; } Biquad;
struct SWMixer {
    _Atomic unsigned gainBits, peakBits, balanceBits, eqBits[SW_EQ_BANDS], rateBits;
    _Atomic bool failed;
    // Render-thread state only.
    float current, balance, appliedEQ[SW_EQ_BANDS], appliedRate;
    bool eqActive, bandActive[SW_EQ_BANDS];
    Biquad bands[SW_EQ_BANDS];
    double z[SW_EQ_BANDS][2][2];
};
static unsigned bits(float f) { unsigned b; memcpy(&b, &f, 4); return b; }
static float value(unsigned b) { float f; memcpy(&f, &b, 4); return f; }
static float clampf(float v, float lo, float hi, float fallback) { return isfinite(v) ? fminf(hi, fmaxf(lo, v)) : fallback; }

SWMixer *SWMixerCreate(void) {
    SWMixer *m = calloc(1, sizeof(SWMixer));
    if (!m) return NULL;
    atomic_init(&m->gainBits, bits(1)); atomic_init(&m->peakBits, bits(0)); atomic_init(&m->balanceBits, bits(0));
    for (int i = 0; i < SW_EQ_BANDS; i++) atomic_init(&m->eqBits[i], bits(0));
    atomic_init(&m->rateBits, bits(48000)); atomic_init(&m->failed, false);
    m->current = 1; m->appliedRate = 48000;
    return m;
}
void SWMixerDestroy(SWMixer *m) { free(m); }
void SWMixerSetGain(SWMixer *m, float g) { atomic_store_explicit(&m->gainBits, bits(clampf(g, 0, SW_MAX_GAIN, 1)), memory_order_relaxed); }
void SWMixerSetBalance(SWMixer *m, float b) { atomic_store_explicit(&m->balanceBits, bits(clampf(b, -1, 1, 0)), memory_order_relaxed); }
void SWMixerSetEQ(SWMixer *m, const float *db, int count) {
    for (int i = 0; i < SW_EQ_BANDS; i++) {
        const float gain = db && i < count ? clampf(db[i], -SW_EQ_RANGE, SW_EQ_RANGE, 0) : 0;
        atomic_store_explicit(&m->eqBits[i], bits(gain), memory_order_relaxed);
    }
}
void SWMixerSetSampleRate(SWMixer *m, double rate) {
    if (isfinite(rate) && rate >= 8000 && rate <= 768000) atomic_store_explicit(&m->rateBits, bits((float)rate), memory_order_relaxed);
}
float SWMixerPeak(SWMixer *m) { return value(atomic_exchange_explicit(&m->peakBits, bits(0), memory_order_relaxed)); }
bool SWMixerFormatFailed(SWMixer *m) { return atomic_load_explicit(&m->failed, memory_order_relaxed); }

// Boost only: transparent below the knee, then a smooth tanh curve that never exceeds 1.0.
static float limit(float s) {
    const float knee = 0.8f, a = fabsf(s);
    if (a <= knee) return s;
    return copysignf(knee + (1 - knee) * tanhf((a - knee) / (1 - knee)), s);
}
// RBJ Audio EQ Cookbook peaking filter, one octave wide. Math only; safe on the render thread.
static Biquad peaking(double freq, double db, double rate) {
    const double A = pow(10, db / 40), w = 2 * M_PI * fmin(freq, rate * 0.45) / rate, c = cos(w), alpha = sin(w) / (2 * 1.41);
    const double a0 = 1 + alpha / A;
    return (Biquad){ (1 + alpha * A) / a0, -2 * c / a0, (1 - alpha * A) / a0, -2 * c / a0, (1 - alpha / A) / a0 };
}
static void updateEQ(SWMixer *m) {
    float db[SW_EQ_BANDS], rate = value(atomic_load_explicit(&m->rateBits, memory_order_relaxed));
    bool changed = rate != m->appliedRate;
    for (int i = 0; i < SW_EQ_BANDS; i++) { db[i] = value(atomic_load_explicit(&m->eqBits[i], memory_order_relaxed)); changed |= db[i] != m->appliedEQ[i]; }
    if (!changed) return;
    static const double freqs[SW_EQ_BANDS] = { 32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000 };
    bool active = false;
    for (int i = 0; i < SW_EQ_BANDS; i++) {
        // Bands above Nyquist cannot be represented. Do not fold their boost into audible bands.
        const bool on = fabsf(db[i]) > 0.01f && freqs[i] < rate * 0.5;
        m->bands[i] = peaking(freqs[i], db[i], rate);
        // A band that turns on starts from silence to avoid a click; running bands keep their memory.
        if (on && !m->bandActive[i]) memset(m->z[i], 0, sizeof m->z[i]);
        m->bandActive[i] = on; m->appliedEQ[i] = db[i]; active |= on;
    }
    m->eqActive = active; m->appliedRate = rate;
}
static float filter(SWMixer *m, float x, UInt32 ch) {
    double y = x;
    for (int i = 0; i < SW_EQ_BANDS; i++) {
        if (!m->bandActive[i]) continue;
        const Biquad *q = &m->bands[i]; double *z = m->z[i][ch];
        const double out = q->b0 * y + z[0];
        z[0] = q->b1 * y - q->a1 * out + z[1];
        z[1] = q->b2 * y - q->a2 * out;
        y = out;
    }
    return (float)y;
}

OSStatus SWMixerRender(AudioObjectID device, const AudioTimeStamp *now,
    const AudioBufferList *input, const AudioTimeStamp *inputTime,
    AudioBufferList *output, const AudioTimeStamp *outputTime, void *context) {
    SWMixer *m = context;
    for (UInt32 b = 0; b < output->mNumberBuffers; b++)
        if (output->mBuffers[b].mData) memset(output->mBuffers[b].mData, 0, output->mBuffers[b].mDataByteSize);
    // Aggregate has no physical input channels: its only input is the stereo tap (mono is duplicated).
    // Output may be mono (Bluetooth hands-free during calls), stereo, or multichannel, where
    // stereo goes to the first two channels and the rest stay silent.
    if (!input->mNumberBuffers || !output->mNumberBuffers) return noErr;
    UInt32 inChannels = 0, outChannels = 0;
    for (UInt32 b = 0; b < input->mNumberBuffers; b++) inChannels += input->mBuffers[b].mNumberChannels;
    for (UInt32 b = 0; b < output->mNumberBuffers; b++) outChannels += output->mBuffers[b].mNumberChannels;
    if (inChannels < 1 || inChannels > 2 || outChannels < 1) { atomic_store(&m->failed, true); return noErr; }
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
    updateEQ(m);
    const float target = value(atomic_load_explicit(&m->gainBits, memory_order_relaxed));
    const float balanceTarget = value(atomic_load_explicit(&m->balanceBits, memory_order_relaxed));
    float peak = 0;
    for (UInt32 f = 0; f < frames; f++) {
        m->current += (target - m->current) * 0.002f;
        m->balance += (balanceTarget - m->balance) * 0.002f;
        const float side[2] = { fminf(1, 1 - m->balance), fminf(1, 1 + m->balance) };
        // Limiting applies only when something can push samples past unity; otherwise audio is untouched.
        const bool shape = m->current > 1.0001f || m->eqActive;
        float stereo[2] = {0, 0}; UInt32 channel = 0;
        for (UInt32 b = 0; b < input->mNumberBuffers; b++) {
            const AudioBuffer *a = &input->mBuffers[b]; const float *samples = a->mData;
            for (UInt32 c = 0; c < a->mNumberChannels; c++, channel++) {
                const float s = samples[f * a->mNumberChannels + c];
                stereo[channel] = isfinite(s) ? s : 0;
            }
        }
        if (inChannels == 1) stereo[1] = stereo[0];
        for (UInt32 c = 0; c < 2; c++) {
            float s = stereo[c];
            if (m->eqActive) s = filter(m, s, c);
            s *= m->current * side[c];
            if (shape) s = limit(s);
            stereo[c] = s;
        }
        const float mono = 0.5f * (stereo[0] + stereo[1]);
        // Peak is measured after processing so meters show what is actually heard.
        peak = fmaxf(peak, outChannels == 1 ? fabsf(mono) : fmaxf(fabsf(stereo[0]), fabsf(stereo[1])));
        channel = 0;
        for (UInt32 b = 0; b < output->mNumberBuffers; b++) {
            AudioBuffer *a = &output->mBuffers[b]; float *samples = a->mData;
            for (UInt32 c = 0; c < a->mNumberChannels; c++, channel++)
                if (channel < 2) samples[f * a->mNumberChannels + c] = outChannels == 1 ? mono : stereo[channel];
        }
    }
    unsigned old = atomic_load_explicit(&m->peakBits, memory_order_relaxed);
    while (value(old) < peak && !atomic_compare_exchange_weak_explicit(&m->peakBits, &old, bits(peak), memory_order_relaxed, memory_order_relaxed)) {}
    return noErr;
}

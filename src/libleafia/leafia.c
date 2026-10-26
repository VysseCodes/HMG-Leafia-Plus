/*
 * libleafia.so - a real AAC-LC -> PCM AudioConverter for the Gen5W CarPlay stack.
 *
 * libCarPlayUtils.so ships AudioConverterNew/SetProperty/FillComplexBuffer/Reset/
 * Dispose as stubs that always fail (-6735), so wireless CarPlay music (AAC-LC on
 * the buffered MainHigh stream) kills the session. The patched libCarPlayUtils
 * forwards those five calls here (dlopen + dlsym "lfa_<name>").
 *
 * Codecs come from the head unit's own Android libraries; nothing is bundled:
 *   'aac '  -> 'lpcm'  music      FDK decoder in libstagefright_soft_aacdec.so
 *   'opus'  -> 'lpcm'  Siri/calls libopus.so decoder
 *   'lpcm'  -> 'opus'  microphone libopus.so encoder
 * Every other pair still returns -6735 exactly like stock.
 *
 * Platform ASBD (0x24 bytes, from the stub): u32 sampleRate, formatID, flags,
 * bytesPerPacket, framesPerPacket, bytesPerFrame, channelsPerFrame, bitsPerChannel,
 * reserved.  Callback contract matches Apple's AudioConverterFillComplexBuffer.
 */
#ifdef HOST
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
typedef unsigned int u32;
typedef int s32;
typedef unsigned char u8;
typedef short s16;
void *dlopen(const char *, int);
void *dlsym(void *, const char *);
#define __android_log_print(p, t, ...) (printf(__VA_ARGS__), printf("\n"))
#else
typedef unsigned int u32;
typedef int s32;
typedef unsigned char u8;
typedef short s16;
typedef unsigned int size_t;

extern void *malloc(size_t);
extern void *calloc(size_t, size_t);
extern void free(void *);
extern void *memcpy(void *, const void *, size_t);
extern void *memset(void *, int, size_t);
extern void *dlopen(const char *, int);
extern void *dlsym(void *, const char *);
extern int __android_log_print(int prio, const char *tag, const char *fmt, ...);

#endif

#define TAG "LeafiaAAC"
#define LOGI(...) __android_log_print(4, TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(5, TAG, __VA_ARGS__)

#define kUnsupportedErr  (-6735)
#define kNoMemoryErr     (-6728)
#define kParamErr        (-6705)
#define FMT_AAC  0x61616320u   /* 'aac ' */
#define FMT_LPCM 0x6c70636du   /* 'lpcm' */
#define FMT_OPUS 0x6f707573u   /* 'opus' */

typedef struct {
    u32 sampleRate, formatID, formatFlags, bytesPerPacket, framesPerPacket,
        bytesPerFrame, channelsPerFrame, bitsPerChannel, reserved;
} ASBD;

typedef struct { u32 mNumberChannels; u32 mDataByteSize; void *mData; } AudioBuffer;
typedef struct { u32 mNumberBuffers; AudioBuffer mBuffers[1]; } AudioBufferList;
typedef struct { long long mStartOffset; u32 mVariableFramesInPacket; u32 mDataByteSize; } ASPD;

typedef s32 (*InputProc)(void *conv, u32 *ioNumberDataPackets, AudioBufferList *ioData,
                         ASPD **outDesc, void *userData);

/* Fraunhofer FDK (Android 4.4 libAACdec) */
typedef void *fdk_handle;
typedef struct { s32 sampleRate; s32 frameSize; s32 numChannels; } CStreamInfoHead;
typedef fdk_handle (*fOpen)(s32 transportFmt, u32 nrOfLayers);
typedef s32 (*fConfigRaw)(fdk_handle, u8 *conf[], const u32 length[]);
typedef s32 (*fFill)(fdk_handle, u8 *buf[], const u32 size[], u32 *bytesValid);
typedef s32 (*fDecode)(fdk_handle, s16 *pcm, s32 pcmSamples, u32 flags);
typedef CStreamInfoHead *(*fInfo)(fdk_handle);
typedef s32 (*fSetParam)(fdk_handle, s32 param, s32 value);
typedef void (*fClose)(fdk_handle);

static struct {
    int tried, ok;
    fOpen open; fConfigRaw configRaw; fFill fill; fDecode decode;
    fInfo info; fSetParam setParam; fClose close;
} F;

/* libopus */
typedef void *(*oDecCreate)(s32 fs, s32 ch, s32 *err);
typedef s32 (*oDecode)(void *st, const u8 *data, s32 len, s16 *pcm, s32 frameSize, s32 fec);
typedef void (*oDestroy)(void *st);
typedef void *(*oEncCreate)(s32 fs, s32 ch, s32 application, s32 *err);
typedef s32 (*oEncode)(void *st, const s16 *pcm, s32 frameSize, u8 *data, s32 maxBytes);
typedef s32 (*oCtl)(void *st, s32 request, ...);
static struct {
    int tried, ok;
    oDecCreate decCreate; oDecode decode; oDestroy decDestroy; oCtl decCtl;
    oEncCreate encCreate; oEncode encode; oDestroy encDestroy; oCtl encCtl;
} O;
#define OPUS_APPLICATION_VOIP 2048
#define OPUS_RESET_STATE 4028

#define TT_MP4_RAW 0
#define AAC_TPDEC_CLEAR_BUFFER 0x0603
#define MAX_FRAMES 5760          /* AAC-LC is 1024; Opus can be up to 120 ms @ 48k */
#define MAX_CH 2

enum { K_AAC_DEC = 1, K_OPUS_DEC = 2, K_OPUS_ENC = 3 };

typedef struct {
    u32 magic;
    int kind;
    ASBD in, out;
    fdk_handle dec;      /* FDK (K_AAC_DEC) */
    void *op;            /* opus decoder or encoder */
    u32 encFrames;       /* K_OPUS_ENC: frames per packet */
    s16 *pcm;            /* decoded, not yet handed out: frames * channels */
    u32 pcmFrames;       /* frames in pcm[] still pending */
    u32 pcmPos;          /* first pending frame */
    u32 packets, errors;
} Conv;
#define CONV_MAGIC 0x4146414cu  /* LAFA */

static int load_fdk(void)
{
    static const char *libs[] = { "libstagefright_soft_aacdec.so", "libbt-codec_aac_dec.so" };
    unsigned i;
    if (F.tried) return F.ok;
    F.tried = 1;
    for (i = 0; i < 2 && !F.ok; i++) {
        void *h = dlopen(libs[i], 0);
        if (!h) continue;
        F.open = (fOpen)dlsym(h, "aacDecoder_Open");
        F.configRaw = (fConfigRaw)dlsym(h, "aacDecoder_ConfigRaw");
        F.fill = (fFill)dlsym(h, "aacDecoder_Fill");
        F.decode = (fDecode)dlsym(h, "aacDecoder_DecodeFrame");
        F.info = (fInfo)dlsym(h, "aacDecoder_GetStreamInfo");
        F.setParam = (fSetParam)dlsym(h, "aacDecoder_SetParam");
        F.close = (fClose)dlsym(h, "aacDecoder_Close");
        F.ok = F.open && F.configRaw && F.fill && F.decode && F.info && F.close;
        LOGI("FDK from %s: %s", libs[i], F.ok ? "ok" : "missing symbols");
    }
    return F.ok;
}

static int load_opus(void)
{
    void *h;
    if (O.tried) return O.ok;
    O.tried = 1;
    h = dlopen("libopus.so", 0);
    if (!h) { LOGW("libopus.so not found"); return 0; }
    O.decCreate = (oDecCreate)dlsym(h, "opus_decoder_create");
    O.decode = (oDecode)dlsym(h, "opus_decode");
    O.decDestroy = (oDestroy)dlsym(h, "opus_decoder_destroy");
    O.decCtl = (oCtl)dlsym(h, "opus_decoder_ctl");
    O.encCreate = (oEncCreate)dlsym(h, "opus_encoder_create");
    O.encode = (oEncode)dlsym(h, "opus_encode");
    O.encDestroy = (oDestroy)dlsym(h, "opus_encoder_destroy");
    O.encCtl = (oCtl)dlsym(h, "opus_encoder_ctl");
    O.ok = O.decCreate && O.decode && O.decDestroy && O.encCreate && O.encode && O.encDestroy;
    LOGI("libopus: %s", O.ok ? "ok" : "missing symbols");
    return O.ok;
}

static int opus_rate_ok(u32 sr)
{
    return sr == 8000 || sr == 12000 || sr == 16000 || sr == 24000 || sr == 48000;
}

/* frames per packet for the encoder: the ASBD value if Opus accepts it, else 20 ms */
static u32 opus_frames(u32 sr, u32 fpp)
{
    u32 ms25 = sr / 400;   /* 2.5 ms */
    u32 m[6] = { 1, 2, 4, 8, 16, 24 };   /* 2.5, 5, 10, 20, 40, 60 ms */
    int i;
    for (i = 0; i < 6; i++) if (fpp == ms25 * m[i]) return fpp;
    return ms25 * 8;
}

static int sr_index(u32 sr)
{
    static const u32 t[] = { 96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050,
                             16000, 12000, 11025, 8000, 7350 };
    int i;
    for (i = 0; i < 13; i++) if (t[i] == sr) return i;
    return -1;
}

static Conv *conv_alloc(const ASBD *in, const ASBD *out, int kind)
{
    Conv *c = (Conv *)calloc(1, sizeof(Conv));
    if (!c) return 0;
    c->pcm = (s16 *)malloc(MAX_FRAMES * MAX_CH * sizeof(s16));
    if (!c->pcm) { free(c); return 0; }
    c->magic = CONV_MAGIC;
    c->kind = kind;
    c->in = *in;
    c->out = *out;
    return c;
}

static void conv_free(Conv *c)
{
    c->magic = 0;
    free(c->pcm);
    free(c);
}

static s32 new_aac_dec(const ASBD *in, const ASBD *out, void **outConv)
{
    Conv *c;
    u8 asc[2], *ascp[1];
    u32 ascl[1];
    int idx = sr_index(in->sampleRate);
    if (idx < 0 || !load_fdk()) return kUnsupportedErr;
    c = conv_alloc(in, out, K_AAC_DEC);
    if (!c) return kNoMemoryErr;
    c->dec = F.open(TT_MP4_RAW, 1);
    if (!c->dec) { conv_free(c); return kNoMemoryErr; }
    /* AudioSpecificConfig: AAC-LC (2), sampling index, channel config */
    asc[0] = (u8)((2 << 3) | (idx >> 1));
    asc[1] = (u8)(((idx & 1) << 7) | (in->channelsPerFrame << 3));
    ascp[0] = asc; ascl[0] = 2;
    if (F.configRaw(c->dec, ascp, ascl) != 0) {
        LOGW("ConfigRaw failed");
        F.close(c->dec); conv_free(c);
        return kUnsupportedErr;
    }
    LOGI("AAC-LC decoder up: %u Hz, %u ch, %u frames/packet", in->sampleRate,
         in->channelsPerFrame, in->framesPerPacket);
    *outConv = c;
    return 0;
}

static s32 new_opus_dec(const ASBD *in, const ASBD *out, void **outConv)
{
    Conv *c;
    s32 err = 0;
    if (!opus_rate_ok(in->sampleRate) || !load_opus()) return kUnsupportedErr;
    c = conv_alloc(in, out, K_OPUS_DEC);
    if (!c) return kNoMemoryErr;
    c->op = O.decCreate((s32)in->sampleRate, (s32)in->channelsPerFrame, &err);
    if (!c->op || err != 0) { LOGW("opus_decoder_create err %d", err); conv_free(c); return kUnsupportedErr; }
    LOGI("Opus decoder up: %u Hz, %u ch", in->sampleRate, in->channelsPerFrame);
    *outConv = c;
    return 0;
}

static s32 new_opus_enc(const ASBD *in, const ASBD *out, void **outConv)
{
    Conv *c;
    s32 err = 0;
    if (!opus_rate_ok(out->sampleRate) || !load_opus()) return kUnsupportedErr;
    c = conv_alloc(in, out, K_OPUS_ENC);
    if (!c) return kNoMemoryErr;
    c->op = O.encCreate((s32)out->sampleRate, (s32)out->channelsPerFrame, OPUS_APPLICATION_VOIP, &err);
    if (!c->op || err != 0) { LOGW("opus_encoder_create err %d", err); conv_free(c); return kUnsupportedErr; }
    c->encFrames = opus_frames(out->sampleRate, out->framesPerPacket);
    LOGI("Opus encoder up: %u Hz, %u ch, %u frames/packet (asked %u)", out->sampleRate,
         out->channelsPerFrame, c->encFrames, out->framesPerPacket);
    *outConv = c;
    return 0;
}

s32 lfa_AudioConverterNew(const ASBD *in, const ASBD *out, void **outConv)
{
    if (!in || !out || !outConv) return kParamErr;
    *outConv = 0;
    if (in->sampleRate != out->sampleRate || in->channelsPerFrame != out->channelsPerFrame ||
        in->channelsPerFrame == 0 || in->channelsPerFrame > MAX_CH) {
        LOGW("unsupported shape %08x %u Hz %u ch -> %08x %u Hz %u ch", in->formatID, in->sampleRate,
             in->channelsPerFrame, out->formatID, out->sampleRate, out->channelsPerFrame);
        return kUnsupportedErr;
    }
    if (in->formatID == FMT_AAC && out->formatID == FMT_LPCM && out->bitsPerChannel == 16)
        return new_aac_dec(in, out, outConv);
    if (in->formatID == FMT_OPUS && out->formatID == FMT_LPCM && out->bitsPerChannel == 16)
        return new_opus_dec(in, out, outConv);
    if (in->formatID == FMT_LPCM && out->formatID == FMT_OPUS && in->bitsPerChannel == 16)
        return new_opus_enc(in, out, outConv);
    LOGW("unsupported conversion %08x -> %08x", in->formatID, out->formatID);
    return kUnsupportedErr;
}

s32 lfa_AudioConverterDispose(void *conv)
{
    Conv *c = (Conv *)conv;
    if (!c || c->magic != CONV_MAGIC) return kParamErr;
    LOGI("%s closed after %u packets (%u errors)",
         c->kind == K_AAC_DEC ? "AAC decoder" : c->kind == K_OPUS_DEC ? "Opus decoder" : "Opus encoder",
         c->packets, c->errors);
    if (c->kind == K_AAC_DEC && c->dec) F.close(c->dec);
    if (c->kind == K_OPUS_DEC && c->op) O.decDestroy(c->op);
    if (c->kind == K_OPUS_ENC && c->op) O.encDestroy(c->op);
    conv_free(c);
    return 0;
}

s32 lfa_AudioConverterReset(void *conv)
{
    Conv *c = (Conv *)conv;
    if (!c || c->magic != CONV_MAGIC) return kParamErr;
    c->pcmFrames = 0;
    c->pcmPos = 0;
    if (c->kind == K_AAC_DEC && F.setParam) F.setParam(c->dec, AAC_TPDEC_CLEAR_BUFFER, 1);
    if (c->kind == K_OPUS_DEC && O.decCtl) O.decCtl(c->op, OPUS_RESET_STATE);
    if (c->kind == K_OPUS_ENC && O.encCtl) O.encCtl(c->op, OPUS_RESET_STATE);
    return 0;
}

s32 lfa_AudioConverterSetProperty(void *conv, u32 prop, u32 size, const void *data)
{
    Conv *c = (Conv *)conv;
    (void)prop; (void)size; (void)data;
    if (!c || c->magic != CONV_MAGIC) return kParamErr;
    return 0;   /* nothing tunable; the ASC is derived from the ASBD */
}

/* decode one compressed packet into c->pcm; on error emit one packet of silence */
static void decode_packet(Conv *c, u8 *data, u32 len)
{
    u8 *bufs[1];
    u32 sizes[1], valid;
    s32 err;
    u32 ch = c->in.channelsPerFrame;
    u32 frames = c->in.framesPerPacket ? c->in.framesPerPacket : 1024;
    CStreamInfoHead *si;

    c->pcmPos = 0;
    c->pcmFrames = 0;
    if (c->kind == K_OPUS_DEC) {
        s32 n = O.decode(c->op, data, (s32)len, c->pcm, MAX_FRAMES, 0);
        c->packets++;
        if (n > 0) {
            c->pcmFrames = (u32)n;
            if (c->packets == 1) LOGI("first Opus packet decoded: %d frames", n);
            return;
        }
        err = n;
        frames = c->in.framesPerPacket ? c->in.framesPerPacket : c->in.sampleRate / 50;
        goto silence;
    }
    bufs[0] = data; sizes[0] = len; valid = len;
    err = F.fill(c->dec, bufs, sizes, &valid);
    if (err == 0) err = F.decode(c->dec, c->pcm, MAX_FRAMES * MAX_CH, 0);
    c->packets++;
    if (err == 0 && (si = F.info(c->dec)) != 0 && si->frameSize > 0 &&
        (u32)si->frameSize <= MAX_FRAMES && (u32)si->numChannels == ch) {
        c->pcmFrames = (u32)si->frameSize;
        if (c->packets == 1)
            LOGI("first packet decoded: %d frames, %d ch, %d Hz", si->frameSize, si->numChannels, si->sampleRate);
        return;
    }
silence:
    c->errors++;
    if (c->errors <= 5 || (c->errors & 255) == 0)
        LOGW("decode error 0x%x on packet %u (%u bytes) - inserting silence", err, c->packets, len);
    if (frames > MAX_FRAMES) frames = MAX_FRAMES;
    memset(c->pcm, 0, frames * ch * sizeof(s16));
    c->pcmFrames = frames;
}

/*
 * microphone: pull PCM from the callback until one Opus frame is buffered, encode it.
 * Produces up to *ioOutputDataPacketSize packets (the core asks for 1), each with
 * a packet description. Partial input stays buffered for the next call.
 */
static s32 fill_encode(Conv *c, InputProc proc, void *userData, u32 *ioPackets,
                       AudioBufferList *outData, ASPD *outDesc)
{
    u32 ch = c->in.channelsPerFrame;
    u32 bpf = ch * sizeof(s16);
    u32 want = *ioPackets, made = 0, used = 0;
    u32 cap = outData->mBuffers[0].mDataByteSize;
    u8 *dst = (u8 *)outData->mBuffers[0].mData;
    s32 status = 0;
    while (made < want) {
        while (c->pcmFrames < c->encFrames) {
            u32 n = c->encFrames - c->pcmFrames;
            u32 got;
            AudioBufferList abl;
            ASPD *pd = 0;
            memset(&abl, 0, sizeof(abl));
            abl.mNumberBuffers = 1;
            status = proc(c, &n, &abl, &pd, userData);
            if (status != 0 || n == 0 || !abl.mBuffers[0].mData) goto out;
            got = abl.mBuffers[0].mDataByteSize >> (ch == 2 ? 2 : 1);
            if (got > n) got = n;
            if (got > c->encFrames - c->pcmFrames) got = c->encFrames - c->pcmFrames;
            memcpy((u8 *)c->pcm + c->pcmFrames * bpf, abl.mBuffers[0].mData, got * bpf);
            c->pcmFrames += got;
        }
        {
            s32 nb;
            if (cap - used < 64) break;
            nb = O.encode(c->op, c->pcm, (s32)c->encFrames, dst + used, (s32)(cap - used));
            c->pcmFrames = 0;
            c->packets++;
            if (nb <= 0) {
                c->errors++;
                if (c->errors <= 5) LOGW("opus_encode error %d", nb);
                continue;
            }
            if (c->packets == 1) LOGI("first Opus packet encoded: %d bytes", nb);
            if (outDesc) {
                outDesc[made].mStartOffset = used;
                outDesc[made].mVariableFramesInPacket = 0;
                outDesc[made].mDataByteSize = (u32)nb;
            }
            used += (u32)nb;
            made++;
        }
    }
out:
    *ioPackets = made;
    outData->mBuffers[0].mDataByteSize = used;
    return made == want ? 0 : status;
}

s32 lfa_AudioConverterFillComplexBuffer(void *conv, InputProc proc, void *userData,
                                        u32 *ioOutputDataPacketSize,
                                        AudioBufferList *outData, ASPD *outDesc)
{
    Conv *c = (Conv *)conv;
    u32 want, done = 0, ch, bpf, cap;
    s32 status = 0;
    u8 *dst;
    (void)outDesc;
    if (!c || c->magic != CONV_MAGIC || !proc || !ioOutputDataPacketSize || !outData ||
        outData->mNumberBuffers < 1 || !outData->mBuffers[0].mData) return kParamErr;
    if (c->kind == K_OPUS_ENC)
        return fill_encode(c, proc, userData, ioOutputDataPacketSize, outData, outDesc);
    ch = c->out.channelsPerFrame;
    bpf = ch * sizeof(s16);                 /* 2 or 4: no division helper on this target */
    want = *ioOutputDataPacketSize;
    cap = outData->mBuffers[0].mDataByteSize >> (ch == 2 ? 2 : 1);
    if (want > cap) want = cap;
    dst = (u8 *)outData->mBuffers[0].mData;

    while (done < want) {
        if (c->pcmFrames == 0) {
            u32 n = 1;
            AudioBufferList abl;
            ASPD *pd = 0;
            memset(&abl, 0, sizeof(abl));
            abl.mNumberBuffers = 1;
            status = proc(conv, &n, &abl, &pd, userData);
            if (status != 0 || n == 0 || !abl.mBuffers[0].mData || abl.mBuffers[0].mDataByteSize == 0)
                break;
            if (pd && pd->mDataByteSize && pd->mDataByteSize <= abl.mBuffers[0].mDataByteSize)
                decode_packet(c, (u8 *)abl.mBuffers[0].mData + (u32)pd->mStartOffset, pd->mDataByteSize);
            else
                decode_packet(c, (u8 *)abl.mBuffers[0].mData, abl.mBuffers[0].mDataByteSize);
            continue;
        }
        {
            u32 take = c->pcmFrames;
            if (take > want - done) take = want - done;
            memcpy(dst + done * bpf, (u8 *)c->pcm + c->pcmPos * bpf, take * bpf);
            done += take;
            c->pcmPos += take;
            c->pcmFrames -= take;
        }
    }
    *ioOutputDataPacketSize = done;
    outData->mBuffers[0].mDataByteSize = done * bpf;
    return done == want ? 0 : status;
}

/*
 * Zero-allocation protobuf walker and in-place rewriter.
 *
 * Design constraints that drove this file:
 *   1. No large stack objects. Spotify callbacks run on 512 KiB threads, and an
 *      earlier 448 KiB table per parser overflowed the stack (SIGBUS crash).
 *   2. No per-field allocations. Fields are walked on demand with a cursor; the
 *      only heap use is one output buffer per response.
 *   3. No oversized output. A rewriter that only deletes or replaces same-size
 *      fields can always be written back into a buffer of the original size.
 *
 * A message is walked with SGPWCur. Reading a field is O(1) and the walk is
 * O(fields); there is no tree, no recursion, no scratch memory.
 */
#ifndef SG_PROTO_REWRITE_CORE_H
#define SG_PROTO_REWRITE_CORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#define SGPW_MAX_BYTES ((size_t)2 * 1024 * 1024)
#define SGPW_MAX_DEPTH 10
#define SGPW_SCRATCH   ((size_t)8 * 1024)

typedef enum { SGPW_OK = 0, SGPW_UNCHANGED, SGPW_LIMIT, SGPW_BAD, SGPW_NO_SPACE } SGPWStatus;
typedef struct { SGPWStatus status; size_t size; } SGPWResult;

typedef struct {
    const char *scope, *name;
    char kind;               /* 'b' bool, 'i' int, 'e' enum string, 'n' none */
    long long value;
    const char *text;
    const char *policy, *realm, *realmId;
} SGProtoRule;

/* One decoded field header. Payload bytes stay in the caller's buffer. */
typedef struct {
    uint32_t number;
    unsigned wire;
    size_t start, keyEnd, payload, length, end;
} SGPWField;

/* Forward-only cursor over one message level. */
typedef struct {
    const uint8_t *p;
    size_t n, at;
} SGPWCur;

static inline void SGPWCurInit(SGPWCur *c, const uint8_t *p, size_t n) {
    c->p = p; c->n = n; c->at = 0;
}
static inline uint8_t SGPWCurDone(const SGPWCur *c) { return c->at >= c->n; }

static inline bool SGPWVarint(const uint8_t *p, size_t n, size_t *at, uint64_t *v) {
    uint64_t x = 0;
    size_t i = *at;
    for (unsigned k = 0; k < 10; ++k) {
        if (i >= n) return false;
        uint8_t b = p[i++];
        if (k == 9 && b > 1) return false;
        x |= (uint64_t)(b & 127) << (7 * k);
        if (!(b & 128)) { *at = i; *v = x; return true; }
    }
    return false;
}

/* Reads the next field. Groups are rejected: never guess a layout. */
static inline bool SGPWCurNext(SGPWCur *c, SGPWField *f) {
    size_t at = c->at;
    if (at >= c->n) return false;
    f->start = at;
    uint64_t key = 0, value = 0;
    if (!SGPWVarint(c->p, c->n, &at, &key) || key > UINT32_MAX || !(key >> 3)) return false;
    f->number = (uint32_t)(key >> 3);
    f->wire = (unsigned)(key & 7);
    f->keyEnd = at;
    switch (f->wire) {
        case 0:
            if (!SGPWVarint(c->p, c->n, &at, &value)) return false;
            break;
        case 1:
            if (c->n - at < 8) return false;
            at += 8;
            break;
        case 2:
            if (!SGPWVarint(c->p, c->n, &at, &value) || value > c->n - at) return false;
            f->payload = at;
            f->length = (size_t)value;
            at += f->length;
            break;
        case 5:
            if (c->n - at < 4) return false;
            at += 4;
            break;
        default:
            return false;
    }
    f->end = at;
    c->at = at;
    return true;
}

/* First field with this number, from wherever the cursor is. */
static inline bool SGPWCurFind(SGPWCur *c, uint32_t number, SGPWField *out) {
    SGPWField f;
    while (SGPWCurNext(c, &f)) {
        if (f.number == number) { if (out) *out = f; return true; }
    }
    return false;
}

static inline bool SGPWEq(const char *a, size_t an, const char *b) {
    size_t bn = b ? strlen(b) : 0;
    return an == bn && (an == 0 || memcmp(a, b, an) == 0);
}

/* ---------------- writer ----------------
 * Emits forward into a caller buffer. Nested levels keep their length prefix
 * fixed-width (five bytes for tags, five for lengths), so the body never has to
 * move and no space is reclaimed; the caller gets a padded but valid message.
 * Protobuf parsers accept non-minimal varints, and the extra bytes are bounded
 * by 10 per nesting level.
 */
typedef struct {
    uint8_t *bytes;
    size_t used, capacity;
    size_t depth;
} SGPWOut;

static inline bool SGPWPut(SGPWOut *o, const void *src, size_t n) {
    if (o->bytes) {                       /* measure pass (bytes == NULL) never writes */
        if (o->used > o->capacity || n > o->capacity - o->used) return false;
        if (n) memcpy(o->bytes + o->used, src, n);
    }
    o->used += n;
    return true;
}
static inline size_t SGPWVarLen(uint64_t v) {
    size_t n = 1;
    while (v > 127) { v >>= 7; ++n; }
    return n;
}
/* Four continuation bytes followed by the low group: always five bytes. */
static inline bool SGPWFixedVarint(SGPWOut *o, uint64_t v, size_t groups) {
    uint8_t b[5];
    for (size_t i = 0; i < groups; ++i) {
        b[i] = (uint8_t)((v & 127) | 128);
        v >>= 7;
    }
    b[groups] = (uint8_t)(v & 127);
    return SGPWPut(o, b, groups + 1);
}
static inline bool SGPWVarOut(SGPWOut *o, uint64_t v) {
    uint8_t b[10];
    size_t n = 0;
    do { b[n++] = (uint8_t)((v & 127) | (v > 127 ? 128 : 0)); v >>= 7; } while (v);
    return SGPWPut(o, b, n);
}
/* Opens a level. The tag and a 5-byte length placeholder are written now; the
 * body follows and SGPWEnd() fills the placeholder, sliding the body back over
 * the unused tail so the encoded message stays compact. */
static inline bool SGPWBegin(SGPWOut *o, uint32_t number, size_t *marker, size_t *body) {
    if (o->depth == SGPW_MAX_DEPTH) return false;
    if (!SGPWFixedVarint(o, ((uint64_t)number << 3) | 2, 4)) return false;
    *marker = o->used;
    if (!SGPWPut(o, "\0\0\0\0\0", 5)) return false;
    *body = o->used;
    ++o->depth;
    return true;
}
static inline bool SGPWEnd(SGPWOut *o, size_t marker, size_t body) {
    if (o->depth == 0) return false;
    if (body < marker || body > o->used) return false;   /* caller passed a stale pair */
    size_t len = o->used - body;
    if ((uint64_t)len >= ((uint64_t)1 << 35)) return false;  /* never fits 5 bytes */
    uint8_t v[5];
    size_t n = 0;
    uint64_t x = len;
    do { v[n++] = (uint8_t)((x & 127) | (x > 127 ? 128 : 0)); x >>= 7; } while (x);
    size_t slack = 5 - n;
    if (o->bytes) {
        if (slack) memmove(o->bytes + marker + n, o->bytes + body, len);
        memcpy(o->bytes + marker, v, n);
    }
    o->used -= slack;
    --o->depth;
    return true;
}
static inline bool SGPWBytes(SGPWOut *o, uint32_t number, const void *src, size_t n) {
    return SGPWVarOut(o, ((uint64_t)number << 3) | 2) && SGPWVarOut(o, n) && SGPWPut(o, src, n);
}
static inline bool SGPWString(SGPWOut *o, uint32_t number, const char *s) {
    return SGPWBytes(o, number, s, s ? strlen(s) : 0);
}
static inline bool SGPWUInt(SGPWOut *o, uint32_t number, uint64_t v) {
    return SGPWVarOut(o, ((uint64_t)number << 3) | 0) && SGPWVarOut(o, v);
}
static inline bool SGPWRaw(SGPWOut *o, const uint8_t *p, const SGPWField *f) {
    return SGPWPut(o, p + f->start, f->end - f->start);
}

#endif

/*
 * Account attributes and remote configuration rewrite (mirror of
 * spotify-proto.js). Single pass, no scratch message, no per-field allocation:
 * fields are walked with a cursor and copied straight into the output buffer.
 *
 * Worst-case output size is larger than the input because the override table is
 * injected. Callers must therefore reserve SGPWOutputBound(); the response hook
 * re-encodes into a buffer of that size and hands back exactly SGPWResult.size.
 */
#ifndef SG_PROTO_REWRITE_H
#define SG_PROTO_REWRITE_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "SGProtoRewriteCore.h"
#include "SGProtoRules.inc"

typedef enum {
    SGPW_TARGET_NONE = 0,
    SGPW_TARGET_ATTRS,       /* AccountAttributesResponse: map entries at field 1 */
    SGPW_TARGET_RESOLVER,    /* ResolveResponse { Configuration configuration = 1 } */
    SGPW_TARGET_BOOTSTRAP,   /* BootstrapResponse { ucs = 2, trials = 3 } */
    SGPW_TARGET_CUSTOMIZE    /* UcsResponseWrapper { success = 1 } */
} SGPWTarget;

/* Worst case: every input byte copied plus every table entry emitted at its
 * longest (tag + two lengths + metadata + value) plus the attribute set. */
#define SGPW_OUT_PER_ENTRY 192
#define SGPW_OUT_ATTRS (48 * 96)
static inline size_t SGPWOutputBound(size_t n) {
    return n + SG_PROTO_OVERRIDE_COUNT * SGPW_OUT_PER_ENTRY + SGPW_OUT_ATTRS + SGPW_MAX_DEPTH * 10 + 64;
}

/* ---------- account attribute set (mirrors modifyAttributes) ---------- */
typedef struct { const char *key, *text; unsigned char kind; } SGPWAttr;  /* 0 bool, 1 string, 2 date */

static const SGPWAttr kSGPWAttrs[] = {
    {"ads", NULL, 0}, {"ab-ad-player-targeting", "0", 1},
    {"allow-advertising-id-transmission", NULL, 0},
    {"restrict-advertising-id-transmission", NULL, 0},
    {"can_use_superbird", NULL, 0}, {"catalogue", "premium", 1},
    {"financial-product", "pr:premium,tc:0", 1},
    {"is-eligible-premium-unboxing", NULL, 0}, {"name", "Spotify Premium", 1},
    {"nft-disabled", "1", 1}, {"offline", NULL, 0}, {"on-demand", NULL, 0},
    {"payments-initial-campaign", "default", 1},
    {"player-license", "premium", 1}, {"player-license-v2", "premium", 1},
    {"product-expiry", NULL, 2},
    {"shuffle-eligible", NULL, 0}, {"social-session", NULL, 0},
    {"social-session-free-tier", NULL, 0}, {"streaming-rules", "", 1},
    {"subscription-enddate", NULL, 2}, {"type", "premium", 1},
    {"unrestricted", NULL, 0},
};
#define SGPW_ATTR_COUNT (sizeof(kSGPWAttrs)/sizeof(kSGPWAttrs[0]))

static inline bool SGPWAttrTrue(const char *key) {
    return !(strcmp(key, "ads") == 0 || strcmp(key, "allow-advertising-id-transmission") == 0 ||
             strcmp(key, "social-session-free-tier") == 0);
}

static inline bool SGPWAttrRemoved(const char *key, size_t len) {
    static const char *const fixed[] = {
        "ad-use-adlogic", "ad-catalogues", "shuffle", "payment-state",
        "last-premium-activation-date", "on-demand-trial", "on-demand-trial-in-progress",
        "smart-shuffle", "at-signal", "feature-set-id-masked", "strider-key",
        "is-eligible-for-trial", "is-eligible-for-upsell", "upsell-state",
        "ad-session-persistence", "ad-formats-preroll-video", "is-premium-eligible",
    };
    for (size_t i = 0; i < sizeof(fixed)/sizeof(fixed[0]); ++i)
        if (SGPWEq(key, len, fixed[i])) return true;
    static const char prefix[] = "is-premium-eligible-v";
    size_t plen = sizeof(prefix) - 1;
    if (len <= plen || memcmp(key, prefix, plen)) return false;
    for (size_t i = plen; i < len; ++i)
        if (key[i] < '0' || key[i] > '9') return false;
    return true;
}

/* ISO8601 UTC, one year ahead. Civil-from-days keeps this free of gmtime_r. */
static inline size_t SGPWExpiry(char out[32]) {
    long long secs = (long long)time(NULL) + 365 * 86400LL;
    long long days = secs / 86400, rem = secs % 86400;
    if (rem < 0) { rem += 86400; --days; }
    long long z = days + 719468;
    long long era = (z >= 0 ? z : z - 146096) / 146097;
    unsigned long long doe = (unsigned long long)(z - era * 146097);
    unsigned long long yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    long long y = (long long)yoe + era * 400;
    unsigned long long doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    unsigned long long mp = (5 * doy + 2) / 153;
    unsigned long long d = doy - (153 * mp + 2) / 5 + 1;
    unsigned long long m = mp < 10 ? mp + 3 : mp - 9;
    if (m <= 2) ++y;
    int n = snprintf(out, 32, "%04lld-%02llu-%02lluT%02lld:%02lld:%02lld.000Z",
                     y, m, d, rem / 3600, (rem % 3600) / 60, rem % 60);
    return n > 0 ? (size_t)n : 0;
}

static inline const SGProtoRule *SGPWFindRule(const SGProtoRule *t, size_t n,
                                              const char *s, size_t sl,
                                              const char *name, size_t nl) {
    for (size_t i = 0; i < n; ++i)
        if (SGPWEq(s, sl, t[i].scope) && SGPWEq(name, nl, t[i].name)) return &t[i];
    return NULL;
}
static inline bool SGPWBlocked(const char *s, size_t sl, const char *name, size_t nl) {
    return SGPWFindRule(kSGProtoBlacklist, SG_PROTO_BLACKLIST_COUNT, s, sl, name, nl) != NULL;
}
static inline bool SGPWKeyInTable(const char *key, size_t len) {
    for (size_t i = 0; i < SGPW_ATTR_COUNT; ++i)
        if (strlen(kSGPWAttrs[i].key) == len && !memcmp(kSGPWAttrs[i].key, key, len)) return true;
    return false;
}

/* ---------- account attribute map ---------- */

/* One map entry: key + the attribute the module dictates. */
static inline bool SGPWAttrEntry(SGPWOut *o, const SGPWAttr *a, const char *iso) {
    size_t em = 0, eb = 0, vm = 0, vb = 0;
    if (!SGPWBegin(o, 1, &em, &eb)) return false;      /* map entry */
    if (!SGPWString(o, 1, a->key)) return false;       /* entry.key */
    if (!SGPWBegin(o, 2, &vm, &vb)) return false;      /* entry.value: AccountAttribute */
    if (!(a->kind == 0 ? SGPWUInt(o, 2, SGPWAttrTrue(a->key) ? 1 : 0)
                       : SGPWString(o, 4, a->kind == 1 ? a->text : iso))) return false;
    return SGPWEnd(o, vm, vb) && SGPWEnd(o, em, eb);
}

/* Copies entries whose key the module leaves alone. */
static inline bool SGPWAttrKeep(SGPWOut *o, const uint8_t *p, size_t n) {
    SGPWCur c;
    SGPWCurInit(&c, p, n);
    SGPWField f;
    while (SGPWCurNext(&c, &f)) {
        if (f.number != 1 || f.wire != 2) { if (!SGPWRaw(o, p, &f)) return false; continue; }
        const uint8_t *e = p + f.payload;
        size_t keyLen = 0;
        const char *key = NULL;
        SGPWCur inner;
        SGPWCurInit(&inner, e, f.length);
        SGPWField k;
        if (!SGPWCurFind(&inner, 1, &k) || k.wire != 2) return false;
        key = (const char *)e + k.payload;
        keyLen = k.length;
        if (SGPWKeyInTable(key, keyLen) || SGPWAttrRemoved(key, keyLen)) continue;
        if (!SGPWRaw(o, p, &f)) return false;
    }
    return true;
}

static inline bool SGPWAttrs(SGPWOut *o, const uint8_t *p, size_t n, const char *iso) {
    /* A response with no account attributes is left to the caller. */
    SGPWCur c;
    SGPWCurInit(&c, p, n);
    SGPWField first;
    if (!SGPWCurFind(&c, 1, &first)) return false;
    for (size_t i = 0; i < SGPW_ATTR_COUNT; ++i)
        if (!SGPWAttrEntry(o, &kSGPWAttrs[i], iso)) return false;
    return SGPWAttrKeep(o, p, n);
}

/* ---------- assigned values ---------- */

static inline bool SGPWRuleValue(SGPWOut *o, const SGProtoRule *r, size_t *marker, size_t *body) {
    if (r->kind == 'n') return true;
    uint32_t field = r->kind == 'b' ? 3 : r->kind == 'i' ? 4 : 5;
    if (!SGPWBegin(o, field, marker, body)) return false;
    bool ok = r->kind == 'b' ? SGPWUInt(o, 1, r->value ? 1 : 0)
             : r->kind == 'i' ? SGPWUInt(o, 1, (uint64_t)r->value)
             : SGPWString(o, 1, r->text);
    return ok && SGPWEnd(o, *marker, *body);
}

static inline bool SGPWRuleEntry(SGPWOut *o, const SGProtoRule *r) {
    size_t m0 = 0, b0 = 0;
    if (!SGPWBegin(o, 1, &m0, &b0)) return false;          /* propertyId */
    if (!SGPWString(o, 1, r->scope) || !SGPWString(o, 2, r->name)) return false;
    if (!SGPWEnd(o, m0, b0)) return false;
    bool meta = (r->policy && *r->policy) || (r->realm && *r->realm) || (r->realmId && *r->realmId);
    if (meta) {
        if (!SGPWBegin(o, 2, &m0, &b0)) return false;      /* metadata */
        if ((r->policy && *r->policy && !SGPWUInt(o, 1, strtoull(r->policy, NULL, 10))) ||
            (r->realm && *r->realm && !SGPWString(o, 2, r->realm)) ||
            (r->realmId && *r->realmId && !SGPWUInt(o, 3, strtoull(r->realmId, NULL, 10)))) return false;
        if (!SGPWEnd(o, m0, b0)) return false;
    }
    size_t vm = 0, vb = 0;
    return SGPWRuleValue(o, r, &vm, &vb);
}

/* Identifier strings inside one AssignedValue body. */
static inline bool SGPWIdent(const uint8_t *e, size_t elen, const char **sc, size_t *sl,
                             const char **nm, size_t *nl) {
    SGPWCur c, idc;
    SGPWCurInit(&c, e, elen);
    SGPWField pid, s, n;
    if (!SGPWCurFind(&c, 1, &pid) || pid.wire != 2) return false;
    const uint8_t *ps = e + pid.payload;
    SGPWCurInit(&idc, ps, pid.length);
    if (!SGPWCurFind(&idc, 1, &s) || s.wire != 2) return false;
    SGPWCur reinit;
    SGPWCurInit(&reinit, ps, pid.length);
    if (!SGPWCurFind(&reinit, 2, &n) || n.wire != 2) return false;
    *sc = (const char *)ps + s.payload; *sl = s.length;
    *nm = (const char *)ps + n.payload; *nl = n.length;
    return true;
}

/* Configuration body: table entries first (blacklist wins), then untouched originals. */
static inline bool SGPWValues(SGPWOut *o, const uint8_t *p, size_t n) {
    size_t m0 = 0, b0 = 0;
    for (size_t i = 0; i < SG_PROTO_OVERRIDE_COUNT; ++i) {
        const SGProtoRule *r = &kSGProtoOverrides[i];
        if (SGPWBlocked(r->scope, strlen(r->scope), r->name, strlen(r->name))) continue;
        if (!SGPWBegin(o, 3, &m0, &b0)) return false;      /* AssignedValue */
        if (!SGPWRuleEntry(o, r)) return false;
        if (!SGPWEnd(o, m0, b0)) return false;
    }
    SGPWCur c;
    SGPWCurInit(&c, p, n);
    SGPWField f;
    while (SGPWCurNext(&c, &f)) {
        if (f.number != 3 || f.wire != 2) { if (!SGPWRaw(o, p, &f)) return false; continue; }
        const uint8_t *e = p + f.payload;
        const char *sc = NULL, *nm = NULL;
        size_t sl = 0, nl = 0;
        if (!SGPWIdent(e, f.length, &sc, &sl, &nm, &nl)) return false;
        if (SGPWBlocked(sc, sl, nm, nl)) continue;
        if (!SGPWFindRule(kSGProtoOverrides, SG_PROTO_OVERRIDE_COUNT, sc, sl, nm, nl)) {
            if (!SGPWRaw(o, p, &f)) return false;
        }
    }
    return true;
}

/* ---------- nested replacement ---------- */

typedef bool (*SGPWBodyFn)(SGPWOut *o, const uint8_t *p, size_t n, const void *ctx);

static inline bool SGPWReplace(SGPWOut *o, const uint8_t *p, size_t n,
                               uint32_t number, SGPWBodyFn fn, const void *ctx) {
    SGPWCur c;
    SGPWCurInit(&c, p, n);
    SGPWField f;
    size_t marker = 0, body = 0;
    bool done = false;
    while (SGPWCurNext(&c, &f)) {
        if (!done && f.number == number && f.wire == 2) {
            if (!SGPWBegin(o, number, &marker, &body)) return false;
            if (!fn(o, p + f.payload, f.length, ctx)) return false;
            if (!SGPWEnd(o, marker, body)) return false;
            done = true;
            continue;
        }
        if (!SGPWRaw(o, p, &f)) return false;
    }
    return done;
}

static inline bool SGPWAttrsBody(SGPWOut *o, const uint8_t *p, size_t n, const void *ctx) {
    return SGPWAttrs(o, p, n, (const char *)ctx);
}
static inline bool SGPWValuesBody(SGPWOut *o, const uint8_t *p, size_t n, const void *ctx) {
    (void)ctx;
    return SGPWValues(o, p, n);
}
/* ResolveResponse { configuration = 1 }; its body is one Configuration level. */
static inline bool SGPWResolveBody(SGPWOut *o, const uint8_t *p, size_t n, const void *ctx) {
    return SGPWValuesBody(o, p, n, ctx);
}
/* UcsResponse { resolve = 1, attrs = 3 } */
static inline bool SGPWUcsBody(SGPWOut *o, const uint8_t *p, size_t n, const void *ctx) {
    SGPWCur c;
    SGPWCurInit(&c, p, n);
    SGPWField f;
    size_t m0 = 0, b0 = 0;
    bool touched = false;
    while (SGPWCurNext(&c, &f)) {
        if (!touched && f.number == 1 && f.wire == 2) {
            /* ResolveResponse: replace its configuration (1) with the value table. */
            if (!SGPWBegin(o, 1, &m0, &b0)) return false;
            if (!SGPWReplace(o, p + f.payload, f.length, 1, SGPWValuesBody, (const char *)ctx)) return false;
            if (!SGPWEnd(o, m0, b0)) return false;
            touched = true;
            continue;
        }
        if (f.number == 3 && f.wire == 2) {
            if (!SGPWBegin(o, 3, &m0, &b0)) return false;
            if (!SGPWAttrs(o, p + f.payload, f.length, (const char *)ctx)) return false;
            if (!SGPWEnd(o, m0, b0)) return false;
            touched = true;
            continue;
        }
        if (!SGPWRaw(o, p, &f)) return false;
    }
    return touched;
}
/* UcsResponseWrapper { success = 1 } */
static inline bool SGPWUcsWrapperBody(SGPWOut *o, const uint8_t *p, size_t n, const void *ctx) {
    return SGPWReplace(o, p, n, 1, SGPWUcsBody, ctx);
}
/* UcsResponseWrapperSuccess { customization = 1 } */
static inline bool SGPWCustomizeBody(SGPWOut *o, const uint8_t *p, size_t n, const void *ctx) {
    return SGPWReplace(o, p, n, 1, SGPWUcsWrapperBody, ctx);
}
/* BootstrapResponse { ucs = 2, trials = 3 }.
 * The ucs body is CustomizationMessageWrapper { oneMoreWrapper = 1 }
 * -> CustomizationMessageOneMoreWrapper { message = 1 }
 * -> CustomizeMessage { response = 1 } -> UcsResponse { resolve = 1, attributes = 3 }.
 * SGPWCustomizeBody() walks the last three hops (the same wrapper chain as the
 * customize response), so four levels are opened before UcsResponse. */
static inline bool SGPWBootstrapBody(SGPWOut *o, const uint8_t *p, size_t n, const void *ctx) {
    SGPWCur c;
    SGPWCurInit(&c, p, n);
    SGPWField f;
    size_t m0 = 0, b0 = 0;
    bool touched = false;
    while (SGPWCurNext(&c, &f)) {
        if (f.number == 3) { touched = true; continue; }
        if (f.number == 2 && f.wire == 2) {
            if (!SGPWBegin(o, 2, &m0, &b0)) return false;
            if (!SGPWReplace(o, p + f.payload, f.length, 1, SGPWCustomizeBody, ctx)) return false;
            if (!SGPWEnd(o, m0, b0)) return false;
            touched = true;
            continue;
        }
        if (!SGPWRaw(o, p, &f)) return false;
    }
    return touched;
}

/* ---------- entry point ---------- */

/* Rewrites `p` into `out`. Pass out == NULL with capacity >= SGPWOutputBound(n)
 * to measure only (the hook always knows the bound, so a single pass suffices). */
static inline SGPWResult SGPWRewrite(const uint8_t *p, size_t n, SGPWTarget target,
                                     uint8_t *out, size_t capacity) {
    SGPWResult r = { SGPW_BAD, n };
    if (n > SGPW_MAX_BYTES) { r.status = SGPW_LIMIT; return r; }
    if ((!p && n) || target == SGPW_TARGET_NONE) return r;
    char iso[32];
    SGPWExpiry(iso);
    SGPWOut o;
    memset(&o, 0, sizeof o);
    o.bytes = out;
    o.capacity = capacity;
    bool ok;
    switch (target) {
        case SGPW_TARGET_ATTRS:     ok = SGPWAttrs(&o, p, n, iso); break;
        case SGPW_TARGET_BOOTSTRAP: ok = SGPWBootstrapBody(&o, p, n, iso); break;
        case SGPW_TARGET_CUSTOMIZE: ok = SGPWCustomizeBody(&o, p, n, iso); break;
        case SGPW_TARGET_RESOLVER:  ok = SGPWReplace(&o, p, n, 1, SGPWResolveBody, iso); break;
        default: return r;
    }
    if (!ok) { r.status = SGPW_NO_SPACE; return r; }
    r.status = SGPW_OK;
    r.size = o.used;
    return r;
}

#endif

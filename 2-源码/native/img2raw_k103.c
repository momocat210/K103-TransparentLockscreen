/* img2raw_k103: decode an arbitrary PNG/JPEG into a 1404x1872 RGBA raw.
 *
 * Usage: img2raw_k103 <file> [fit|cover|stretch]
 *        img2raw_k103 - [fit|cover|stretch]   (read image bytes from stdin)
 * stdout: exactly 1404*1872*4 bytes RGBA.
 *
 * fit     : scale to fit, centered, transparent padding (keeps transparent PNGs working)
 * cover   : scale to cover, center-crop to full screen (best for photos / JPG)
 * stretch : force exactly 1404x1872 (may distort)
 *
 * Built as a static aarch64-linux-musl ELF with zig cc; no runtime deps.
 */
#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_PNG
#define STBI_ONLY_JPEG
#define STBI_NO_HDR
#define STBI_NO_LINEAR
#include "stb_image.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define W 1404
#define H 1872
#define OUTSZ ((size_t)W * H * 4)
#define MAXIN (64 * 1024 * 1024)

static unsigned char *outbuf = NULL;
static unsigned char *inbuf = NULL;

static unsigned char *load_stdin(size_t *len) {
    size_t n = 0, cap = MAXIN;
    inbuf = (unsigned char *)malloc(cap);
    if (!inbuf) { *len = 0; return NULL; }
    while (n < cap) {
        size_t r = fread(inbuf + n, 1, cap - n, stdin);
        n += r;
        if (r == 0) break;
    }
    *len = n;
    return inbuf;
}

static int clampi(int v, int lo, int hi) {
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

int main(int argc, char **argv) {
    const char *path = (argc > 1) ? argv[1] : "-";
    const char *mode = (argc > 2) ? argv[2] : "cover";
    int iw = 0, ih = 0, ch = 0;
    unsigned char *img = NULL;

    outbuf = (unsigned char *)calloc(OUTSZ, 1); /* transparent padding for fit mode */
    if (!outbuf) { fprintf(stderr, "oom\n"); return 9; }

    if (strcmp(path, "-") == 0) {
        size_t len = 0;
        unsigned char *data = load_stdin(&len);
        if (!data || len == 0) { fprintf(stderr, "empty stdin\n"); return 2; }
        img = stbi_load_from_memory(data, (int)len, &iw, &ih, &ch, 4);
    } else {
        img = stbi_load(path, &iw, &ih, &ch, 4);
    }
    if (!img || iw <= 0 || ih <= 0) {
        fprintf(stderr, "decode failed: %s\n", stbi_failure_reason());
        return 3;
    }

    double sx = (double)W / (double)iw;
    double sy = (double)H / (double)ih;
    double s;

    if (strcmp(mode, "stretch") == 0) {
        for (int oy = 0; oy < H; oy++) {
            int syi = clampi((int)((double)oy / sy), 0, ih - 1);
            for (int ox = 0; ox < W; ox++) {
                int sxi = clampi((int)((double)ox / sx), 0, iw - 1);
                memcpy(outbuf + ((size_t)oy * W + ox) * 4, img + ((size_t)syi * iw + sxi) * 4, 4);
            }
        }
    } else {
        s = (strcmp(mode, "fit") == 0) ? (sx < sy ? sx : sy) : (sx > sy ? sx : sy);
        int nw = (int)((double)iw * s);
        int nh = (int)((double)ih * s);
        if (nw < 1) nw = 1;
        if (nh < 1) nh = 1;
        int offx = (W - nw) / 2; /* fit: positive; cover: negative */
        int offy = (H - nh) / 2;
        for (int oy = 0; oy < H; oy++) {
            int iy = oy - offy;
            if (iy < 0 || iy >= nh) continue;
            int syi = clampi((int)((double)iy / s), 0, ih - 1);
            for (int ox = 0; ox < W; ox++) {
                int ix = ox - offx;
                if (ix < 0 || ix >= nw) continue;
                int sxi = clampi((int)((double)ix / s), 0, iw - 1);
                memcpy(outbuf + ((size_t)oy * W + ox) * 4, img + ((size_t)syi * iw + sxi) * 4, 4);
            }
        }
    }

    fwrite(outbuf, 1, OUTSZ, stdout);
    stbi_image_free(img);
    free(outbuf);
    free(inbuf);
    return 0;
}

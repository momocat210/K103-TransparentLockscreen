/* compose_k103: alpha-composite a transparent RGBA sticker over a base frame
 * and write an opaque JPEG (the Boyue lock-screen image format).
 *
 * Usage: compose_k103 <sticker.raw> <frame.raw|frame.png> <out.jpg> <quality> [frame_is_raw]
 *
 *   sticker.raw : 1404*1872*4 RGBA (from img2raw_k103)
 *   frame       : either 1404*1872*4 RGBA raw with a 16-byte screencap header
 *                 (frame_is_raw=1, header auto-skipped), or any PNG/JPEG
 *                 (frame_is_raw=0).
 *   out.jpg     : destination JPEG path (written atomically via stdout not used)
 *   quality     : JPEG quality 1..100 (e.g. 92)
 *
 * The sticker's alpha region shows through to the base frame ("last frame"
 * transparency). Fully transparent sticker pixels keep the base frame; fully
 * opaque pixels replace it. This reproduces the A5 Pro "transparent sticker"
 * effect on K103's JPEG lock screen.
 */
#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_PNG
#define STBI_ONLY_JPEG
#include "stb_image.h"
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define W 1404
#define H 1872
#define RAW ((size_t)W * H * 4)
#define HDR 16

static unsigned char *slurp(const char *path, size_t *out_len) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (n <= 0) { fclose(f); return NULL; }
    unsigned char *b = (unsigned char *)malloc((size_t)n);
    if (!b) { fclose(f); return NULL; }
    if (fread(b, 1, (size_t)n, f) != (size_t)n) { free(b); fclose(f); return NULL; }
    fclose(f);
    *out_len = (size_t)n;
    return b;
}

int main(int argc, char **argv) {
    if (argc < 5) {
        fprintf(stderr, "usage: %s <sticker.raw> <frame> <out.jpg> <quality> [frame_is_raw=1]\n", argv[0]);
        return 2;
    }
    const char *stk_path = argv[1];
    const char *frm_path = argv[2];
    const char *out_path = argv[3];
    int quality = atoi(argv[4]);
    if (quality < 1 || quality > 100) quality = 92;
    int frm_raw = (argc >= 6) ? atoi(argv[5]) : 1;

    size_t stk_len = 0;
    unsigned char *stk = slurp(stk_path, &stk_len);
    if (!stk || stk_len < RAW) { fprintf(stderr, "ERR sticker raw short\n"); free(stk); return 3; }

    unsigned char *base = NULL;
    if (frm_raw) {
        size_t flen = 0;
        unsigned char *fb = slurp(frm_path, &flen);
        if (!fb) { fprintf(stderr, "ERR frame missing\n"); free(stk); return 4; }
        if (flen >= HDR + RAW) base = fb + HDR;      /* screencap header skipped */
        else if (flen >= RAW) base = fb;             /* raw without header */
        else { fprintf(stderr, "ERR frame raw short (%zu)\n", flen); free(fb); free(stk); return 4; }
        /* keep fb alive until after write */
    } else {
        int bw = 0, bh = 0, bc = 0;
        base = stbi_load(frm_path, &bw, &bh, &bc, 4);
        if (!base || bw != W || bh != H) {
            fprintf(stderr, "ERR frame decode/size %dx%d\n", bw, bh);
            stbi_image_free(base); free(stk); return 5;
        }
    }

    /* Alpha composite: out = sticker over base, as opaque RGB. */
    unsigned char *rgb = (unsigned char *)malloc((size_t)W * H * 3);
    if (!rgb) { fprintf(stderr, "ERR oom\n"); free(stk); return 6; }
    for (size_t i = 0; i < (size_t)W * H; ++i) {
        unsigned int a = stk[i * 4 + 3];
        unsigned int inv = 255u - a;
        rgb[i * 3 + 0] = (unsigned char)((base[i * 4 + 0] * inv + stk[i * 4 + 0] * a + 127u) / 255u);
        rgb[i * 3 + 1] = (unsigned char)((base[i * 4 + 1] * inv + stk[i * 4 + 1] * a + 127u) / 255u);
        rgb[i * 3 + 2] = (unsigned char)((base[i * 4 + 2] * inv + stk[i * 4 + 2] * a + 127u) / 255u);
    }

    int ok = stbi_write_jpg(out_path, W, H, 3, rgb, quality);
    free(rgb);
    free(stk);
    if (!ok) { fprintf(stderr, "ERR write jpg\n"); return 7; }
    return 0;
}

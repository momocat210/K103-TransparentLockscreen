/* framecmp_k103: read one screencap raw frame from stdin, compare with cached
 * frame file, and only rewrite the cache when the content actually changed.
 *
 * Usage: screencap | framecmp_k103 <cache.raw>
 *
 * Exit: 0 = changed & cache updated
 *       1 = identical (cache untouched, no disk write)
 *       2 = read error / short input
 *       3 = black frame (screen off race), cache untouched
 *
 * Purpose: avoid writing 10 MB to eMMC every poll; only page turns / screen
 * changes cause a disk write.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>

#define FRAME_SZ 10513168u   /* 1404*1872*4 + 16-byte screencap header */

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: screencap | %s <cache.raw>\n", argv[0]);
        return 2;
    }
    const char *cache = argv[1];
    unsigned char *buf = (unsigned char *)malloc(FRAME_SZ);
    if (!buf) { fprintf(stderr, "oom\n"); return 2; }

    size_t got = 0;
    while (got < FRAME_SZ) {
        ssize_t r = read(0, buf + got, FRAME_SZ - got);
        if (r <= 0) break;
        got += (size_t)r;
    }
    if (got != FRAME_SZ) {
        fprintf(stderr, "short frame %zu\n", got);
        free(buf);
        return 2;
    }

    /* Sample three points (centre / quarter / three-quarter). All-zero means a
     * black frame captured while the panel was powering off -> ignore it. */
    const size_t sample[3] = { 2628304u, 5256592u, 7884880u };
    int all_zero = 1;
    for (int i = 0; i < 3; i++) {
        for (size_t j = 0; j < 64; j++) {
            if (buf[sample[i] + j]) { all_zero = 0; break; }
        }
        if (!all_zero) break;
    }
    if (all_zero) { free(buf); return 3; }

    struct stat st;
    int have_cache = (stat(cache, &st) == 0 && st.st_size == (off_t)FRAME_SZ);

    /* All-0xFF is a likely boot/launcher transition frame. Only reject it when
     * there is no cached frame yet (real white reading pages are still accepted
     * once a frame exists). */
    if (!have_cache) {
        int all_white = 1;
        for (int i = 0; i < 3; i++) {
            for (size_t j = 0; j < 64; j++) {
                if (buf[sample[i] + j] != 0xFF) { all_white = 0; break; }
            }
            if (!all_white) break;
        }
        if (all_white) { free(buf); return 4; }
    }

    int same = 0;
    if (have_cache) {
        int fd = open(cache, O_RDONLY);
        if (fd >= 0) {
            unsigned char *old = (unsigned char *)malloc(FRAME_SZ);
            if (old) {
                size_t rd = 0;
                while (rd < FRAME_SZ) {
                    ssize_t r = read(fd, old + rd, FRAME_SZ - rd);
                    if (r <= 0) break;
                    rd += (size_t)r;
                }
                if (rd == FRAME_SZ && memcmp(old, buf, FRAME_SZ) == 0) same = 1;
                free(old);
            }
            close(fd);
        }
    }
    if (same) { free(buf); return 1; }

    int fd = open(cache, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) { perror("open cache"); free(buf); return 2; }
    size_t wr = 0;
    while (wr < FRAME_SZ) {
        ssize_t w = write(fd, buf + wr, FRAME_SZ - wr);
        if (w <= 0) break;
        wr += (size_t)w;
    }
    close(fd);
    free(buf);
    return (wr == FRAME_SZ) ? 0 : 2;
}
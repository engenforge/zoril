/* A headless stand-in for a native UI toolkit's platform layer, the shape a native application plans:
   create_window / set_frame_callback / blit_rgba / run / destroy. It draws nothing and needs no
   windowing system, so it runs in CI; it keeps a frame count and a checksum of what was blitted
   so the Zoril side can check that its pixels arrived. */
#include <stdlib.h>
#include <string.h>

struct Window {
    int w, h;
    unsigned char *fb;
    void (*cb)(struct Window *, void *);
    void *ud;
    int frames;
    unsigned long checksum;
};

struct Window *create_window(int w, int h) {
    if (w <= 0 || h <= 0) return 0;
    struct Window *win = calloc(1, sizeof *win);
    win->w = w;
    win->h = h;
    win->fb = calloc((size_t)w * h, 4);
    return win;
}

void set_frame_callback(struct Window *win, void (*cb)(struct Window *, void *), void *userdata) {
    win->cb = cb;
    win->ud = userdata;
}

/* The toolkit has no null callback, so "no callback" is a function that does nothing: a real toolkit can
   fire resize, expose and timer events at any time, and once the registered userdata is gone it must
   not be called. */
static void no_callback(struct Window *win, void *ud) { (void)win; (void)ud; }

void clear_frame_callback(struct Window *win) {
    win->cb = no_callback;
    win->ud = 0;
}

void blit_rgba(struct Window *win, const unsigned char *rgba, int w, int h) {
    if (w != win->w || h != win->h) return;
    memcpy(win->fb, rgba, (size_t)w * h * 4);
    for (size_t i = 0; i < (size_t)w * h * 4; i++) win->checksum = win->checksum * 31 + rgba[i];
    win->frames++;
}

void run(struct Window *win) {
    for (int i = 0; i < 3; i++) win->cb(win, win->ud);
}

int window_has_userdata(const struct Window *win) { return win->ud != 0; }
int window_frames(const struct Window *win) { return win->frames; }
unsigned long window_checksum(const struct Window *win) { return win->checksum; }

void destroy(struct Window *win) {
    free(win->fb);
    free(win);
}

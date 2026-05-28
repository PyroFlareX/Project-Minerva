// gamepad-map.c — Map a generic USB gamepad to a virtual keyboard + mouse via
// uinput, so the Torchform QuickShell demo (keyboard-driven) is controllable
// from the pad, Steam-style: right stick moves the cursor.
//
// Build:  gcc -O2 -o gamepad-map gamepad-map.c
// Run:    ./gamepad-map [/dev/input/eventN]   (default: auto-detect "Gamepad")
//
// Needs read access to the gamepad evdev node (group `input`) and write access
// to /dev/uinput (load module, chgrp input /dev/uinput, chmod 660).
//
// Every button event is logged to stderr as `BTN code=0x... val=N -> KEY ...`
// so the physical->logical mapping can be tuned in BUTTON_MAP below.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <dirent.h>
#include <poll.h>
#include <time.h>
#include <linux/input.h>
#include <linux/uinput.h>

// ─── Button -> key mapping (generic DragonRise 0810:0001 BTN_ codes) ──────────
// Tweak the .key column once we know the physical layout from the stderr log.
// Physical layout discovered for this pad (DragonRise 0810:0001). key == -1
// means "emit a left mouse click" instead of a key (see is_click_button).
struct btnmap { int code; int key; const char *note; };
static struct btnmap BUTTON_MAP[] = {
    { 0x123, KEY_A,       "left face (A) / confirm"    },
    { 0x121, KEY_ESC,     "right face (B) / back"      },
    { 0x122, KEY_X,       "bottom face (X) / palette"  },
    { 0x120, KEY_TAB,     "top face (Y) / radial"      },
    { 0x124, KEY_C,       "L1 / notifications"         },
    { 0x125, KEY_Z,       "R1 / quick settings"        },
    { 0x126, KEY_TAB,     "L2 / radial"                },
    { 0x127, -1,          "R2 / left-click"            },
    { 0x128, KEY_SPACE,   "Select / home"              },
    { 0x129, KEY_KPENTER, "Start / switcher"           }, // keypad enter => Qt.Key_Enter
    { 0x12a, -1,          "L3 / left-click"            },
    { 0x12b, -1,          "R3 / left-click"            },
};
#define NBTN ((int)(sizeof(BUTTON_MAP)/sizeof(BUTTON_MAP[0])))

// Buttons that should act as a left mouse click (key == -1 above)
static int is_click_button(int code) {
    return code == 0x127 || code == 0x12a || code == 0x12b;
}

// Right-stick axes used for the mouse cursor (DragonRise: Z = X, RZ = Y)
#define AXIS_MOUSE_X ABS_Z
#define AXIS_MOUSE_Y ABS_RZ
// Left-stick axes used for d-pad-style arrow nav
#define AXIS_NAV_X   ABS_X
#define AXIS_NAV_Y   ABS_Y

#define MOUSE_DEADZONE 0.18   // fraction of half-range
#define MOUSE_MAX_SPEED 18.0  // px per tick at full deflection
#define NAV_THRESHOLD  0.6    // fraction of half-range to trigger an arrow
#define TICK_MS 16            // ~60 Hz
#define REPEAT_DELAY_MS 350   // initial delay before arrow auto-repeat
#define REPEAT_RATE_MS  90    // repeat interval while held

static int uinput_open_kbd(void) {
    int fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
    if (fd < 0) return -1;
    ioctl(fd, UI_SET_EVBIT, EV_KEY);
    int keys[] = { KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_A, KEY_B,
                   KEY_ESC, KEY_X, KEY_Z, KEY_C, KEY_TAB, KEY_SPACE,
                   KEY_ENTER, KEY_KPENTER };
    for (int i = 0; i < (int)(sizeof(keys)/sizeof(keys[0])); i++)
        ioctl(fd, UI_SET_KEYBIT, keys[i]);
    struct uinput_setup us;
    memset(&us, 0, sizeof(us));
    us.id.bustype = BUS_VIRTUAL;
    us.id.vendor = 0x7f01; us.id.product = 0x0001;
    strcpy(us.name, "torchform-gamepad-kbd");
    ioctl(fd, UI_DEV_SETUP, &us);
    ioctl(fd, UI_DEV_CREATE);
    return fd;
}

static int uinput_open_mouse(void) {
    int fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
    if (fd < 0) return -1;
    ioctl(fd, UI_SET_EVBIT, EV_KEY);
    ioctl(fd, UI_SET_KEYBIT, BTN_LEFT);
    ioctl(fd, UI_SET_KEYBIT, BTN_RIGHT);
    ioctl(fd, UI_SET_EVBIT, EV_REL);
    ioctl(fd, UI_SET_RELBIT, REL_X);
    ioctl(fd, UI_SET_RELBIT, REL_Y);
    struct uinput_setup us;
    memset(&us, 0, sizeof(us));
    us.id.bustype = BUS_VIRTUAL;
    us.id.vendor = 0x7f01; us.id.product = 0x0002;
    strcpy(us.name, "torchform-gamepad-mouse");
    ioctl(fd, UI_DEV_SETUP, &us);
    ioctl(fd, UI_DEV_CREATE);
    return fd;
}

static void emit(int fd, int type, int code, int val) {
    struct input_event ev;
    memset(&ev, 0, sizeof(ev));
    ev.type = type; ev.code = code; ev.value = val;
    write(fd, &ev, sizeof(ev));
}
static void syn(int fd) { emit(fd, EV_SYN, SYN_REPORT, 0); }

static void key_tap_state(int fd, int key, int down, int *cur) {
    if (down == *cur) return;
    emit(fd, EV_KEY, key, down);
    syn(fd);
    *cur = down;
}

// Auto-detect the gamepad event node by scanning /dev/input/event* names.
static int find_gamepad(char *out, size_t n) {
    DIR *d = opendir("/dev/input");
    if (!d) return -1;
    struct dirent *e;
    char best[64] = {0};
    while ((e = readdir(d))) {
        if (strncmp(e->d_name, "event", 5) != 0) continue;
        char path[80];
        snprintf(path, sizeof(path), "/dev/input/%s", e->d_name);
        int fd = open(path, O_RDONLY | O_NONBLOCK);
        if (fd < 0) continue;
        char name[256] = {0};
        ioctl(fd, EVIOCGNAME(sizeof(name)), name);
        close(fd);
        for (char *p = name; *p; p++) *p = (*p >= 'A' && *p <= 'Z') ? *p + 32 : *p;
        if (strstr(name, "torchform")) continue;   // skip our own virtual devices
        if (strstr(name, "gamepad") || strstr(name, "joystick") || strstr(name, "controller")) {
            strncpy(best, path, sizeof(best) - 1);
            break;
        }
    }
    closedir(d);
    if (!best[0]) return -1;
    strncpy(out, best, n - 1);
    return 0;
}

struct axis_info { int min, max, mid, half; };
static struct axis_info axis_get(int fd, int code) {
    struct input_absinfo ai;
    struct axis_info a = { 0, 255, 127, 128 };
    if (ioctl(fd, EVIOCGABS(code), &ai) == 0) {
        a.min = ai.minimum; a.max = ai.maximum;
        a.mid = (ai.minimum + ai.maximum) / 2;
        a.half = (ai.maximum - ai.minimum) / 2;
        if (a.half <= 0) a.half = 1;
    }
    return a;
}

static long now_ms(void) {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000L + ts.tv_nsec / 1000000L;
}

int main(int argc, char **argv) {
    char path[64];
    if (argc > 1) { strncpy(path, argv[1], sizeof(path) - 1); path[sizeof(path)-1] = 0; }
    else if (find_gamepad(path, sizeof(path)) != 0) {
        fprintf(stderr, "gamepad-map: no gamepad found; pass /dev/input/eventN\n");
        return 1;
    }
    int gp = open(path, O_RDONLY | O_NONBLOCK);
    if (gp < 0) { fprintf(stderr, "gamepad-map: open %s: %s\n", path, strerror(errno)); return 1; }
    fprintf(stderr, "gamepad-map: reading %s\n", path);

    struct axis_info ax_mx = axis_get(gp, AXIS_MOUSE_X);
    struct axis_info ax_my = axis_get(gp, AXIS_MOUSE_Y);
    struct axis_info ax_nx = axis_get(gp, AXIS_NAV_X);
    struct axis_info ax_ny = axis_get(gp, AXIS_NAV_Y);

    int kbd = uinput_open_kbd();
    int mouse = uinput_open_mouse();
    if (kbd < 0 || mouse < 0) {
        fprintf(stderr, "gamepad-map: cannot open /dev/uinput: %s\n", strerror(errno));
        return 1;
    }

    // Logical arrow state (driven by hat + left stick), with auto-repeat.
    int dirs[4] = {0,0,0,0};            // up,down,left,right currently requested
    int dir_key[4] = { KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT };
    int dir_cur[4] = {0,0,0,0};         // emitted state
    long dir_next[4] = {0,0,0,0};       // next repeat time
    int hat_x = 0, hat_y = 0;           // from ABS_HAT0X/Y
    int nav_x = 0, nav_y = 0;           // from left stick (digital)
    double mvx = 0, mvy = 0;            // normalized right-stick (-1..1)

    long last_tick = now_ms();
    for (;;) {
        struct pollfd pfd = { gp, POLLIN, 0 };
        poll(&pfd, 1, TICK_MS);

        struct input_event ev;
        if (pfd.revents & POLLIN) {
            ssize_t r;
            while ((r = read(gp, &ev, sizeof(ev))) == sizeof(ev)) {
                if (ev.type == EV_KEY) {
                    fprintf(stderr, "BTN code=0x%x val=%d\n", ev.code, ev.value);
                    int handled = 0;
                    for (int i = 0; i < NBTN; i++) {
                        if (BUTTON_MAP[i].code != ev.code) continue;
                        handled = 1;
                        if (is_click_button(ev.code)) {
                            emit(mouse, EV_KEY, BTN_LEFT, ev.value ? 1 : 0);
                            syn(mouse);
                        } else if (BUTTON_MAP[i].key >= 0) {
                            emit(kbd, EV_KEY, BUTTON_MAP[i].key, ev.value ? 1 : 0);
                            syn(kbd);
                        }
                        break;
                    }
                    (void)handled;
                } else if (ev.type == EV_ABS) {
                    switch (ev.code) {
                        case ABS_HAT0X: hat_x = ev.value; break;
                        case ABS_HAT0Y: hat_y = ev.value; break;
                        case AXIS_NAV_X: {
                            double n = (double)(ev.value - ax_nx.mid) / ax_nx.half;
                            nav_x = (n < -NAV_THRESHOLD) ? -1 : (n > NAV_THRESHOLD) ? 1 : 0;
                        } break;
                        case AXIS_NAV_Y: {
                            double n = (double)(ev.value - ax_ny.mid) / ax_ny.half;
                            nav_y = (n < -NAV_THRESHOLD) ? -1 : (n > NAV_THRESHOLD) ? 1 : 0;
                        } break;
                        case AXIS_MOUSE_X: {
                            double n = (double)(ev.value - ax_mx.mid) / ax_mx.half;
                            mvx = (n > -MOUSE_DEADZONE && n < MOUSE_DEADZONE) ? 0 : n;
                        } break;
                        case AXIS_MOUSE_Y: {
                            double n = (double)(ev.value - ax_my.mid) / ax_my.half;
                            mvy = (n > -MOUSE_DEADZONE && n < MOUSE_DEADZONE) ? 0 : n;
                        } break;
                    }
                }
            }
        }

        long t = now_ms();
        if (t - last_tick < TICK_MS) continue;
        last_tick = t;

        // Combine hat + left stick into the four directional requests.
        int up    = (hat_y < 0) || (nav_y < 0);
        int down  = (hat_y > 0) || (nav_y > 0);
        int left  = (hat_x < 0) || (nav_x < 0);
        int right = (hat_x > 0) || (nav_x > 0);
        int want[4] = { up, down, left, right };

        for (int i = 0; i < 4; i++) {
            if (want[i] && !dirs[i]) {            // newly pressed
                dirs[i] = 1;
                key_tap_state(kbd, dir_key[i], 1, &dir_cur[i]);
                emit(kbd, EV_KEY, dir_key[i], 0); syn(kbd); dir_cur[i] = 0; // tap
                dir_next[i] = t + REPEAT_DELAY_MS;
            } else if (want[i] && dirs[i]) {      // held -> auto-repeat
                if (t >= dir_next[i]) {
                    emit(kbd, EV_KEY, dir_key[i], 1); syn(kbd);
                    emit(kbd, EV_KEY, dir_key[i], 0); syn(kbd);
                    dir_next[i] = t + REPEAT_RATE_MS;
                }
            } else if (!want[i] && dirs[i]) {     // released
                dirs[i] = 0;
            }
        }

        // Mouse motion from right stick.
        if (mvx != 0 || mvy != 0) {
            int dx = (int)(mvx * MOUSE_MAX_SPEED);
            int dy = (int)(mvy * MOUSE_MAX_SPEED);
            if (dx) emit(mouse, EV_REL, REL_X, dx);
            if (dy) emit(mouse, EV_REL, REL_Y, dy);
            syn(mouse);
        }
    }
    return 0;
}

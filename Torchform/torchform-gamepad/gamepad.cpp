#include "gamepad.h"

#include <QSocketNotifier>
#include <QTimer>
#include <QFile>
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QByteArray>

#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <linux/input.h>
#include <cerrno>
#include <cstring>

namespace {

constexpr char VIRTPAD_NAME[] = "torchform-virtpad";
constexpr int RETRY_MS = 2000;

// evdev key code -> logical button name. MUST match torchform-inputd's
// virtpad.rs out_key() and button.rs as_str().
QHash<unsigned, QString> buildButtonNames() {
    return {
        {BTN_SOUTH, "south"}, {BTN_EAST, "east"}, {BTN_WEST, "west"}, {BTN_NORTH, "north"},
        {BTN_TL, "l1"}, {BTN_TR, "r1"}, {BTN_TL2, "l2"}, {BTN_TR2, "r2"},
        {BTN_SELECT, "select"}, {BTN_START, "start"}, {BTN_MODE, "mode"},
        {BTN_THUMBL, "thumbl"}, {BTN_THUMBR, "thumbr"},
        {BTN_DPAD_UP, "dpad_up"}, {BTN_DPAD_DOWN, "dpad_down"},
        {BTN_DPAD_LEFT, "dpad_left"}, {BTN_DPAD_RIGHT, "dpad_right"},
    };
}

// evdev abs code -> axis slot (0:leftX 1:leftY 2:rightX 3:rightY 4:l2 5:r2).
QHash<unsigned, int> buildAxisIndex() {
    return {
        {ABS_X, 0}, {ABS_Y, 1}, {ABS_RX, 2}, {ABS_RY, 3}, {ABS_Z, 4}, {ABS_RZ, 5},
    };
}

QString manifestPath() {
    QByteArray runtime = qgetenv("XDG_RUNTIME_DIR");
    QString base = runtime.isEmpty() ? QStringLiteral("/tmp") : QString::fromLocal8Bit(runtime);
    return base + QStringLiteral("/torchform/inputd-actions.json");
}

} // namespace

Gamepad::Gamepad(QObject *parent)
    : QObject(parent)
    , m_buttonNames(buildButtonNames())
    , m_axisIndex(buildAxisIndex())
{
    loadManifest();
    tryOpen();
    if (m_fd < 0) {
        // The daemon should start before us, but be robust to ordering/hotplug.
        m_retry = new QTimer(this);
        m_retry->setInterval(RETRY_MS);
        connect(m_retry, &QTimer::timeout, this, &Gamepad::tryOpen);
        m_retry->start();
    }
}

Gamepad::~Gamepad() {
    closeDevice();
}

bool Gamepad::isPressed(const QString &name) const {
    return m_buttons.value(name, false).toBool();
}

void Gamepad::loadManifest() {
    QFile f(manifestPath());
    if (!f.open(QIODevice::ReadOnly)) {
        return; // no chord/multiclick actions configured, or daemon not up yet
    }
    const QJsonObject root = QJsonDocument::fromJson(f.readAll()).object();
    const QJsonObject actions = root.value("actions").toObject();
    m_actionNames.clear();
    for (auto it = actions.begin(); it != actions.end(); ++it) {
        // manifest is { name: evdev_code }
        m_actionNames.insert(static_cast<unsigned>(it.value().toInt()), it.key());
    }
}

// Scan /dev/input/event* for the virtual pad and open it.
void Gamepad::tryOpen() {
    if (m_fd >= 0) {
        return;
    }
    QDir dir(QStringLiteral("/dev/input"));
    const QStringList nodes = dir.entryList({QStringLiteral("event*")}, QDir::System);
    for (const QString &node : nodes) {
        const QString path = dir.absoluteFilePath(node);
        int fd = ::open(path.toLocal8Bit().constData(), O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        if (fd < 0) {
            continue;
        }
        char name[256] = {0};
        if (::ioctl(fd, EVIOCGNAME(sizeof(name)), name) >= 0 && qstrcmp(name, VIRTPAD_NAME) == 0) {
            m_fd = fd;
            break;
        }
        ::close(fd);
    }
    if (m_fd < 0) {
        return; // try again on the next retry tick
    }

    // Query abs ranges for normalization.
    for (auto it = m_axisIndex.begin(); it != m_axisIndex.end(); ++it) {
        struct input_absinfo info;
        if (::ioctl(m_fd, EVIOCGABS(it.key()), &info) >= 0) {
            Range &r = m_axisRange[it.value()];
            r.min = info.minimum;
            r.max = info.maximum;
            r.known = (info.maximum != info.minimum);
        }
    }
    // Manifest may have appeared after construction; reload now.
    loadManifest();

    m_notifier = new QSocketNotifier(m_fd, QSocketNotifier::Read, this);
    connect(m_notifier, &QSocketNotifier::activated, this, &Gamepad::onReadable);
    if (m_retry) {
        m_retry->stop();
    }
    emit connectedChanged();
}

void Gamepad::closeDevice() {
    if (m_notifier) {
        m_notifier->setEnabled(false);
        m_notifier->deleteLater();
        m_notifier = nullptr;
    }
    if (m_fd >= 0) {
        ::close(m_fd);
        m_fd = -1;
        emit connectedChanged();
    }
    if (m_retry && !m_retry->isActive()) {
        m_retry->start();
    }
}

void Gamepad::onReadable() {
    struct input_event ev;
    ssize_t n;
    while ((n = ::read(m_fd, &ev, sizeof(ev))) == sizeof(ev)) {
        handleEvent(ev.type, ev.code, ev.value);
    }
    if (n < 0 && errno != EAGAIN && errno != EWOULDBLOCK) {
        // Device went away (ENODEV) or other fatal error — drop and retry.
        closeDevice();
    }
}

void Gamepad::handleEvent(unsigned type, unsigned code, int value) {
    if (type == EV_KEY) {
        if (value == 2) {
            return; // kernel autorepeat — the daemon never sends edges as 2
        }
        const bool pressed = (value != 0);
        auto bit = m_buttonNames.constFind(code);
        if (bit != m_buttonNames.constEnd()) {
            const QString &name = bit.value();
            m_buttons.insert(name, pressed);
            emit buttonsChanged();
            if (pressed) {
                emit buttonPressed(name);
            } else {
                emit buttonReleased(name);
            }
            return;
        }
        auto ait = m_actionNames.constFind(code);
        if (ait != m_actionNames.constEnd()) {
            if (pressed) {
                emit actionTriggered(ait.value()); // action is a press+release pulse
            }
            return;
        }
    } else if (type == EV_ABS) {
        auto xit = m_axisIndex.constFind(code);
        if (xit != m_axisIndex.constEnd()) {
            const int idx = xit.value();
            const Range &r = m_axisRange[idx];
            qreal norm = 0.0;
            if (r.known) {
                const qreal t = qreal(value - r.min) / qreal(r.max - r.min); // 0..1
                norm = (idx <= 3) ? (t * 2.0 - 1.0) : t; // sticks -> -1..1, triggers -> 0..1
            }
            if (m_axes[idx] != norm) {
                m_axes[idx] = norm;
                emit axesChanged();
            }
        }
    }
}

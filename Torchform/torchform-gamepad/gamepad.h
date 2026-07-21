// Torchform.Gamepad — a QML type that reads the torchform-inputd virtual gamepad
// (a normal evdev device) and exposes its buttons, axes, and chord/multiclick
// actions to QML. QuickShell (Qt6) has no native gamepad support; this fills the
// gap without faking keypresses. Reads raw <linux/input.h> events via a
// QSocketNotifier — no libevdev/SDL dependency.
//
// QML usage (singleton):
//   import Torchform.Gamepad
//   Connections {
//       target: Gamepad
//       function onButtonPressed(name) { if (name === "south") shell.handleConfirm() }
//       function onActionTriggered(name) { if (name === "switcher") shell.handleSwitcher() }
//   }
//   // or bind held state:  opacity: Gamepad.buttons["l1"] ? 1 : 0.5
//   // or axes:             x: Gamepad.leftX * 100

#pragma once

#include <QObject>
#include <QVariantMap>
#include <QHash>
#include <QString>
#include <QtQml/qqmlregistration.h>

class QSocketNotifier;
class QTimer;

class Gamepad : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    // True while the virtual pad device is open.
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    // Logical button name -> held bool (e.g. buttons["south"]). For binding to
    // held state; edge handling should use the buttonPressed/Released signals.
    Q_PROPERTY(QVariantMap buttons READ buttons NOTIFY buttonsChanged)
    // Sticks normalized to [-1, 1]; triggers to [0, 1].
    Q_PROPERTY(qreal leftX  READ leftX  NOTIFY axesChanged)
    Q_PROPERTY(qreal leftY  READ leftY  NOTIFY axesChanged)
    Q_PROPERTY(qreal rightX READ rightX NOTIFY axesChanged)
    Q_PROPERTY(qreal rightY READ rightY NOTIFY axesChanged)
    Q_PROPERTY(qreal l2     READ l2     NOTIFY axesChanged)
    Q_PROPERTY(qreal r2     READ r2     NOTIFY axesChanged)

public:
    explicit Gamepad(QObject *parent = nullptr);
    ~Gamepad() override;

    bool connected() const { return m_fd >= 0; }
    QVariantMap buttons() const { return m_buttons; }
    qreal leftX()  const { return m_axes[0]; }
    qreal leftY()  const { return m_axes[1]; }
    qreal rightX() const { return m_axes[2]; }
    qreal rightY() const { return m_axes[3]; }
    qreal l2()     const { return m_axes[4]; }
    qreal r2()     const { return m_axes[5]; }

    // Convenience for QML: is a logical button currently held?
    Q_INVOKABLE bool isPressed(const QString &name) const;

signals:
    void connectedChanged();
    void buttonsChanged();
    void axesChanged();
    void buttonPressed(const QString &name);
    void buttonReleased(const QString &name);
    void actionTriggered(const QString &name);

private slots:
    void onReadable();
    void tryOpen();

private:
    void closeDevice();
    void loadManifest();
    void handleEvent(unsigned type, unsigned code, int value);

    static constexpr int AXIS_COUNT = 6;

    int m_fd = -1;
    QSocketNotifier *m_notifier = nullptr;
    QTimer *m_retry = nullptr;

    QVariantMap m_buttons;            // logical name -> bool (held)
    qreal m_axes[AXIS_COUNT] = {0, 0, 0, 0, 0, 0};

    QHash<unsigned, QString> m_buttonNames; // evdev key code -> logical name
    QHash<unsigned, QString> m_actionNames; // evdev key code -> action name (manifest)
    QHash<unsigned, int> m_axisIndex;       // evdev abs code -> 0..5

    struct Range { int min = 0; int max = 0; bool known = false; };
    Range m_axisRange[AXIS_COUNT];
};

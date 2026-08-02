#pragma once

#include <qobject.h>
#include <qqmlintegration.h>
#include <qsocketnotifier.h>
#include <qlist.h>
#include <qstring.h>

#include <xcb/xcb.h>
#include <xcb/composite.h>
#include <xcb/damage.h>
#include <xcb/xtest.h>
#include <xcb/shape.h>

namespace caelestia::services {

class XEmbedService;

class XEmbedClient : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("XEmbedClient cannot be created from QML")

    Q_PROPERTY(quint32 windowId READ windowId CONSTANT)
    Q_PROPERTY(QString title READ title NOTIFY titleChanged)
    Q_PROPERTY(QString wmClass READ wmClass NOTIFY wmClassChanged)
    Q_PROPERTY(int clientWidth READ clientWidth NOTIFY geometryChanged)
    Q_PROPERTY(int clientHeight READ clientHeight NOTIFY geometryChanged)

public:
    explicit XEmbedClient(quint32 winId, xcb_connection_t* conn, QObject* parent = nullptr);
    ~XEmbedClient() override = default;

    [[nodiscard]] quint32 windowId() const { return m_windowId; }
    [[nodiscard]] QString title() const { return m_title; }
    [[nodiscard]] QString wmClass() const { return m_wmClass; }
    [[nodiscard]] int clientWidth() const { return m_width; }
    [[nodiscard]] int clientHeight() const { return m_height; }

    void updateTitle(const QString& title);
    void updateWmClass(const QString& wmClass);
    void updateGeometry(int width, int height);

signals:
    void titleChanged();
    void wmClassChanged();
    void geometryChanged();

private:
    quint32 m_windowId = 0;
    QString m_title;
    QString m_wmClass;
    int m_width = 24;
    int m_height = 24;
};

class XEmbedService : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QList<QObject*> items READ items NOTIFY itemsChanged)
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)

public:
    explicit XEmbedService(QObject* parent = nullptr);
    ~XEmbedService() override;

    static XEmbedService* instance();

    [[nodiscard]] QList<QObject*> items() const { return m_items; }
    [[nodiscard]] int count() const { return static_cast<int>(m_items.size()); }
    [[nodiscard]] bool available() const { return m_available; }

    [[nodiscard]] xcb_connection_t* connection() const { return m_conn; }
    [[nodiscard]] xcb_window_t rootWindow() const { return m_root; }
    [[nodiscard]] xcb_window_t managerWindow() const { return m_managerWin; }
    [[nodiscard]] uint8_t damageEventBase() const { return m_damageEventBase; }

    Q_INVOKABLE void sendClick(quint32 winId, int button, int x, int y, int globalX = 0, int globalY = 0);
    Q_INVOKABLE void sendRelease(quint32 winId, int button, int x, int y, int globalX = 0, int globalY = 0);
    Q_INVOKABLE void sendMotion(quint32 winId, int x, int y, int globalX = 0, int globalY = 0);
    Q_INVOKABLE void sendWheel(quint32 winId, int delta, int x, int y, int globalX = 0, int globalY = 0);

signals:
    void itemsChanged();
    void countChanged();
    void availableChanged();
    void damageReceived(quint32 windowId);
    void windowDestroyed(quint32 windowId);

private slots:
    void processX11Events();

private:
    void initX11();
    void cleanupX11();
    void internAtoms();
    bool claimSelection();
    void dockClient(xcb_window_t clientWin);
    void undockClient(xcb_window_t clientWin);
    void refreshClientProperties(XEmbedClient* client);

    static XEmbedService* s_instance;

    xcb_connection_t* m_conn = nullptr;
    int m_screenNum = 0;
    xcb_window_t m_root = XCB_NONE;
    xcb_window_t m_managerWin = XCB_NONE;
    QSocketNotifier* m_notifier = nullptr;
    bool m_available = false;
    bool m_hasXTest = false;
    uint8_t m_damageEventBase = 0;

    // Atoms
    xcb_atom_t m_trayAtom = XCB_NONE;
    xcb_atom_t m_opcodeAtom = XCB_NONE;
    xcb_atom_t m_orientationAtom = XCB_NONE;
    xcb_atom_t m_iconSizeAtom = XCB_NONE;
    xcb_atom_t m_visualAtom = XCB_NONE;
    xcb_atom_t m_managerAtom = XCB_NONE;
    xcb_atom_t m_xembedAtom = XCB_NONE;
    xcb_atom_t m_xembedInfoAtom = XCB_NONE;
    xcb_atom_t m_netWmNameAtom = XCB_NONE;
    xcb_atom_t m_wmNameAtom = XCB_NONE;
    xcb_atom_t m_wmClassAtom = XCB_NONE;
    xcb_atom_t m_utf8StringAtom = XCB_NONE;

    QList<QObject*> m_items;
    QHash<xcb_window_t, XEmbedClient*> m_clientMap;
};

} // namespace caelestia::services

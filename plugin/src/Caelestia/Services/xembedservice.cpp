#include "xembedservice.hpp"

#include <qloggingcategory.h>
#include <qtimer.h>
#include <cstdlib>
#include <cstring>

#include <xcb/xcb_util.h>
#include <xcb/xfixes.h>
#include <xcb/xtest.h>

Q_LOGGING_CATEGORY(lcXEmbed, "caelestia.services.xembed")

namespace caelestia::services {

constexpr uint32_t SYSTEM_TRAY_REQUEST_DOCK = 0;
constexpr uint32_t SYSTEM_TRAY_BEGIN_MESSAGE = 1;
constexpr uint32_t SYSTEM_TRAY_CANCEL_MESSAGE = 2;

constexpr uint32_t XEMBED_EMBEDDED_NOTIFY = 0;
constexpr uint32_t XEMBED_WINDOW_ACTIVATE = 1;
constexpr uint32_t XEMBED_WINDOW_DEACTIVATE = 2;
constexpr uint32_t XEMBED_FOCUS_IN = 4;
constexpr uint32_t XEMBED_FOCUS_OUT = 5;

XEmbedClient::XEmbedClient(quint32 winId, xcb_connection_t* conn, QObject* parent)
    : QObject(parent)
    , m_windowId(winId) {
    if (!conn || winId == XCB_NONE) {
        return;
    }

    auto geomCookie = xcb_get_geometry(conn, winId);
    auto* geom = xcb_get_geometry_reply(conn, geomCookie, nullptr);
    if (geom) {
        m_width = geom->width > 0 ? geom->width : 24;
        m_height = geom->height > 0 ? geom->height : 24;
        free(geom);
    }
}

void XEmbedClient::updateTitle(const QString& title) {
    if (m_title != title) {
        m_title = title;
        emit titleChanged();
    }
}

void XEmbedClient::updateWmClass(const QString& wmClass) {
    if (m_wmClass != wmClass) {
        m_wmClass = wmClass;
        emit wmClassChanged();
    }
}

void XEmbedClient::updateGeometry(int width, int height) {
    if (m_width != width || m_height != height) {
        m_width = width > 0 ? width : 24;
        m_height = height > 0 ? height : 24;
        emit geometryChanged();
    }
}

XEmbedService* XEmbedService::s_instance = nullptr;

XEmbedService::XEmbedService(QObject* parent)
    : QObject(parent) {
    s_instance = this;
    initX11();
}

XEmbedService::~XEmbedService() {
    cleanupX11();
    if (s_instance == this) {
        s_instance = nullptr;
    }
}

XEmbedService* XEmbedService::instance() {
    return s_instance;
}

void XEmbedService::initX11() {
    const char* displayEnv = std::getenv("DISPLAY");
    if (!displayEnv || std::strlen(displayEnv) == 0) {
        qCDebug(lcXEmbed) << "DISPLAY environment variable not set, XEmbed service disabled";
        return;
    }

    m_conn = xcb_connect(nullptr, &m_screenNum);
    if (xcb_connection_has_error(m_conn)) {
        qCWarning(lcXEmbed) << "Failed to connect to XCB display" << displayEnv;
        m_conn = nullptr;
        return;
    }

    // Query extensions
    const xcb_query_extension_reply_t* compositeReply =
        xcb_get_extension_data(m_conn, &xcb_composite_id);
    if (!compositeReply || !compositeReply->present) {
        qCWarning(lcXEmbed) << "XComposite extension is not present on X server";
        cleanupX11();
        return;
    }

    const xcb_query_extension_reply_t* damageReply =
        xcb_get_extension_data(m_conn, &xcb_damage_id);
    if (!damageReply || !damageReply->present) {
        qCWarning(lcXEmbed) << "XDamage extension is not present on X server";
        cleanupX11();
        return;
    }
    m_damageEventBase = damageReply->first_event;

    auto xtestCookie = xcb_test_get_version(m_conn, XCB_TEST_MAJOR_VERSION, XCB_TEST_MINOR_VERSION);
    auto* xtestReply = xcb_test_get_version_reply(m_conn, xtestCookie, nullptr);
    if (xtestReply) {
        m_hasXTest = true;
        qCDebug(lcXEmbed) << "XTest extension is available, version" << xtestReply->major_version << "." << xtestReply->minor_version;
        std::free(xtestReply);
    } else {
        qCWarning(lcXEmbed) << "XTest extension is NOT available";
    }

    // Get screen
    const xcb_setup_t* setup = xcb_get_setup(m_conn);
    xcb_screen_iterator_t iter = xcb_setup_roots_iterator(setup);
    for (int i = 0; i < m_screenNum && iter.rem; ++i) {
        xcb_screen_next(&iter);
    }
    if (!iter.data) {
        qCWarning(lcXEmbed) << "Failed to obtain default XCB screen";
        cleanupX11();
        return;
    }

    m_root = iter.data->root;

    internAtoms();

    if (!claimSelection()) {
        qCWarning(lcXEmbed) << "Failed to claim _NET_SYSTEM_TRAY selection ownership";
        cleanupX11();
        return;
    }

    int fd = xcb_get_file_descriptor(m_conn);
    m_notifier = new QSocketNotifier(fd, QSocketNotifier::Read, this);
    connect(m_notifier, &QSocketNotifier::activated, this, &XEmbedService::processX11Events);

    m_available = true;
    emit availableChanged();
    qCDebug(lcXEmbed) << "XEmbedService initialized successfully on display" << displayEnv;
}

void XEmbedService::cleanupX11() {
    if (m_notifier) {
        m_notifier->setEnabled(false);
        m_notifier->deleteLater();
        m_notifier = nullptr;
    }

    qDeleteAll(m_items);
    m_items.clear();
    m_clientMap.clear();

    if (m_conn) {
        if (m_managerWin != XCB_NONE) {
            xcb_destroy_window(m_conn, m_managerWin);
            m_managerWin = XCB_NONE;
        }
        xcb_flush(m_conn);
        xcb_disconnect(m_conn);
        m_conn = nullptr;
    }

    if (m_available) {
        m_available = false;
        emit availableChanged();
        emit itemsChanged();
        emit countChanged();
    }
}

void XEmbedService::internAtoms() {
    auto intern = [this](const char* name) -> xcb_atom_t {
        auto cookie = xcb_intern_atom(m_conn, 0, static_cast<uint16_t>(std::strlen(name)), name);
        auto* reply = xcb_intern_atom_reply(m_conn, cookie, nullptr);
        if (!reply) return XCB_NONE;
        xcb_atom_t atom = reply->atom;
        free(reply);
        return atom;
    };

    char trayAtomName[32];
    std::snprintf(trayAtomName, sizeof(trayAtomName), "_NET_SYSTEM_TRAY_S%d", m_screenNum);
    m_trayAtom = intern(trayAtomName);

    m_opcodeAtom = intern("_NET_SYSTEM_TRAY_OPCODE");
    m_orientationAtom = intern("_NET_SYSTEM_TRAY_ORIENTATION");
    m_iconSizeAtom = intern("_NET_SYSTEM_TRAY_ICON_SIZE");
    m_visualAtom = intern("_NET_SYSTEM_TRAY_VISUAL");
    m_managerAtom = intern("MANAGER");
    m_xembedAtom = intern("_XEMBED");
    m_xembedInfoAtom = intern("_XEMBED_INFO");
    m_netWmNameAtom = intern("_NET_WM_NAME");
    m_wmNameAtom = intern("WM_NAME");
    m_wmClassAtom = intern("WM_CLASS");
    m_utf8StringAtom = intern("UTF8_STRING");
}

bool XEmbedService::claimSelection() {
    // Check if another tray is running
    auto ownerCookie = xcb_get_selection_owner(m_conn, m_trayAtom);
    auto* ownerReply = xcb_get_selection_owner_reply(m_conn, ownerCookie, nullptr);
    if (ownerReply && ownerReply->owner != XCB_NONE) {
        qCWarning(lcXEmbed) << "Another system tray is already managing selection" << m_trayAtom;
        free(ownerReply);
        return false;
    }
    if (ownerReply) {
        free(ownerReply);
    }

    // Create manager window with override_redirect = 1
    m_managerWin = xcb_generate_id(m_conn);
    uint32_t mask = XCB_CW_OVERRIDE_REDIRECT | XCB_CW_EVENT_MASK;
    uint32_t values[2] = {
        1, // override_redirect = 1 prevents WM from managing/displaying the manager window
        XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY |
        XCB_EVENT_MASK_STRUCTURE_NOTIFY |
        XCB_EVENT_MASK_PROPERTY_CHANGE
    };

    xcb_create_window(
        m_conn,
        XCB_COPY_FROM_PARENT,
        m_managerWin,
        m_root,
        0, 0, 64, 64, 0,
        XCB_WINDOW_CLASS_INPUT_OUTPUT,
        XCB_COPY_FROM_PARENT,
        mask, values
    );

    // Make manager window transparent / click-through initially
    xcb_rectangle_t initialRect = { 0, 0, 0, 0 };
    xcb_shape_rectangles(m_conn, XCB_SHAPE_SO_SET, XCB_SHAPE_SK_INPUT, 0, m_managerWin, 0, 0, 1, &initialRect);

    // Map manager window so children can become viewable
    xcb_map_window(m_conn, m_managerWin);

    // Set orientation property to horizontal (0)
    uint32_t orientation = 0;
    xcb_change_property(
        m_conn,
        XCB_PROP_MODE_REPLACE,
        m_managerWin,
        m_orientationAtom,
        XCB_ATOM_CARDINAL,
        32, 1, &orientation
    );

    // Set icon size property (24)
    uint32_t iconSize = 24;
    if (m_iconSizeAtom != XCB_NONE) {
        xcb_change_property(
            m_conn,
            XCB_PROP_MODE_REPLACE,
            m_managerWin,
            m_iconSizeAtom,
            XCB_ATOM_CARDINAL,
            32, 1, &iconSize
        );
    }

    // Set _NET_SYSTEM_TRAY_VISUAL
    xcb_visualid_t visualId = XCB_NONE;
    const xcb_setup_t* setup = xcb_get_setup(m_conn);
    xcb_screen_iterator_t screenIter = xcb_setup_roots_iterator(setup);
    for (int i = 0; i < m_screenNum && screenIter.rem; ++i) {
        xcb_screen_next(&screenIter);
    }
    if (screenIter.data) {
        visualId = screenIter.data->root_visual;
        for (auto d = xcb_screen_allowed_depths_iterator(screenIter.data); d.rem; xcb_depth_next(&d)) {
            if (d.data->depth == 32) {
                auto v = xcb_depth_visuals_iterator(d.data);
                if (v.rem && v.data) {
                    visualId = v.data->visual_id;
                    break;
                }
            }
        }
    }
    if (visualId != XCB_NONE && m_visualAtom != XCB_NONE) {
        xcb_change_property(
            m_conn,
            XCB_PROP_MODE_REPLACE,
            m_managerWin,
            m_visualAtom,
            XCB_ATOM_VISUALID,
            32, 1, &visualId
        );
    }

    // Claim selection
    xcb_set_selection_owner(m_conn, m_managerWin, m_trayAtom, XCB_CURRENT_TIME);

    auto verifyCookie = xcb_get_selection_owner(m_conn, m_trayAtom);
    auto* verifyReply = xcb_get_selection_owner_reply(m_conn, verifyCookie, nullptr);
    if (!verifyReply || verifyReply->owner != m_managerWin) {
        qCWarning(lcXEmbed) << "Failed to verify selection ownership of" << m_trayAtom;
        if (verifyReply) free(verifyReply);
        return false;
    }
    free(verifyReply);

    // Broadcast MANAGER message to root window
    xcb_client_message_event_t ev;
    std::memset(&ev, 0, sizeof(ev));
    ev.response_type = XCB_CLIENT_MESSAGE;
    ev.format = 32;
    ev.window = m_root;
    ev.type = m_managerAtom;
    ev.data.data32[0] = XCB_CURRENT_TIME;
    ev.data.data32[1] = m_trayAtom;
    ev.data.data32[2] = m_managerWin;
    ev.data.data32[3] = 0;
    ev.data.data32[4] = 0;

    xcb_send_event(m_conn, 0, m_root, XCB_EVENT_MASK_STRUCTURE_NOTIFY, reinterpret_cast<const char*>(&ev));
    xcb_flush(m_conn);

    return true;
}

void XEmbedService::processX11Events() {
    if (!m_conn) return;

    xcb_generic_event_t* event = nullptr;
    while ((event = xcb_poll_for_event(m_conn)) != nullptr) {
        uint8_t type = static_cast<uint8_t>(event->response_type & 0x7FU);

        if (type == XCB_CLIENT_MESSAGE) {
            auto* cm = reinterpret_cast<xcb_client_message_event_t*>(event);
            qCDebug(lcXEmbed) << "ClientMessage received, type atom:" << cm->type;
            if (cm->type == m_opcodeAtom) {
                uint32_t opcode = cm->data.data32[1];
                qCDebug(lcXEmbed) << "System tray opcode received:" << opcode << "target window:" << cm->data.data32[2];
                if (opcode == SYSTEM_TRAY_REQUEST_DOCK) {
                    xcb_window_t clientWin = cm->data.data32[2];
                    dockClient(clientWin);
                }
            }
        } else if (type == XCB_DESTROY_NOTIFY) {
            auto* dn = reinterpret_cast<xcb_destroy_notify_event_t*>(event);
            undockClient(dn->window);
        } else if (type == XCB_UNMAP_NOTIFY) {
            auto* un = reinterpret_cast<xcb_unmap_notify_event_t*>(event);
            if (m_clientMap.contains(un->window)) {
                // If unmapped, notify items
                emit damageReceived(un->window);
            }
        } else if (type == XCB_PROPERTY_NOTIFY) {
            auto* pn = reinterpret_cast<xcb_property_notify_event_t*>(event);
            if (m_clientMap.contains(pn->window)) {
                refreshClientProperties(m_clientMap.value(pn->window));
            }
        } else if (type == XCB_CONFIGURE_NOTIFY) {
            auto* cn = reinterpret_cast<xcb_configure_notify_event_t*>(event);
            if (m_clientMap.contains(cn->window)) {
                XEmbedClient* client = m_clientMap.value(cn->window);
                client->updateGeometry(cn->width, cn->height);
                emit damageReceived(cn->window);
            }
        } else if (m_damageEventBase != 0 && type == m_damageEventBase + XCB_DAMAGE_NOTIFY) {
            auto* damageEvent = reinterpret_cast<xcb_damage_notify_event_t*>(event);
            xcb_damage_subtract(m_conn, damageEvent->damage, XCB_NONE, XCB_NONE);
            emit damageReceived(damageEvent->drawable);
        }

        std::free(event);
    }
    xcb_flush(m_conn);
}

void XEmbedService::dockClient(xcb_window_t clientWin) {
    if (clientWin == XCB_NONE || m_clientMap.contains(clientWin)) {
        return;
    }

    qCDebug(lcXEmbed) << "Docking XEmbed client window:" << clientWin;

    // Reparent client window into our manager window
    xcb_reparent_window(m_conn, clientWin, m_managerWin, 0, 0);

    // Subscribe to events on client window
    uint32_t val[1] = {
        XCB_EVENT_MASK_STRUCTURE_NOTIFY |
        XCB_EVENT_MASK_PROPERTY_CHANGE
    };
    xcb_change_window_attributes(m_conn, clientWin, XCB_CW_EVENT_MASK, val);

    // Send XEMBED_EMBEDDED_NOTIFY to client
    xcb_client_message_event_t ev;
    std::memset(&ev, 0, sizeof(ev));
    ev.response_type = XCB_CLIENT_MESSAGE;
    ev.format = 32;
    ev.window = clientWin;
    ev.type = m_xembedAtom;
    ev.data.data32[0] = XCB_CURRENT_TIME;
    ev.data.data32[1] = XEMBED_EMBEDDED_NOTIFY;
    ev.data.data32[2] = 0;
    ev.data.data32[3] = m_managerWin;
    ev.data.data32[4] = 0; // version 0

    xcb_send_event(m_conn, 0, clientWin, XCB_EVENT_MASK_NO_EVENT, reinterpret_cast<const char*>(&ev));

    // Configure client window size (24x24) and map
    uint32_t clientSize[4] = { 0, 0, 24, 24 };
    xcb_configure_window(m_conn, clientWin, XCB_CONFIG_WINDOW_X | XCB_CONFIG_WINDOW_Y | XCB_CONFIG_WINDOW_WIDTH | XCB_CONFIG_WINDOW_HEIGHT, clientSize);

    // Map the client window
    xcb_map_window(m_conn, clientWin);
    xcb_flush(m_conn);

    auto* client = new XEmbedClient(clientWin, m_conn, this);
    refreshClientProperties(client);

    m_clientMap.insert(clientWin, client);
    m_items.append(client);

    emit itemsChanged();
    emit countChanged();
}

void XEmbedService::undockClient(xcb_window_t clientWin) {
    if (!m_clientMap.contains(clientWin)) {
        return;
    }

    qCDebug(lcXEmbed) << "Undocking XEmbed client window:" << clientWin;
    XEmbedClient* client = m_clientMap.take(clientWin);
    m_items.removeAll(client);

    emit windowDestroyed(clientWin);
    emit itemsChanged();
    emit countChanged();

    client->deleteLater();
}

void XEmbedService::refreshClientProperties(XEmbedClient* client) {
    if (!client || !m_conn) return;

    xcb_window_t win = client->windowId();

    // Query _NET_WM_NAME or WM_NAME
    auto netNameCookie = xcb_get_property(m_conn, 0, win, m_netWmNameAtom, m_utf8StringAtom, 0, 1024);
    auto* netNameReply = xcb_get_property_reply(m_conn, netNameCookie, nullptr);
    if (netNameReply && xcb_get_property_value_length(netNameReply) > 0) {
        QString title = QString::fromUtf8(
            reinterpret_cast<const char*>(xcb_get_property_value(netNameReply)),
            xcb_get_property_value_length(netNameReply)
        );
        client->updateTitle(title);
        std::free(netNameReply);
    } else {
        if (netNameReply) std::free(netNameReply);
        auto wmNameCookie = xcb_get_property(m_conn, 0, win, m_wmNameAtom, XCB_ATOM_STRING, 0, 1024);
        auto* wmNameReply = xcb_get_property_reply(m_conn, wmNameCookie, nullptr);
        if (wmNameReply && xcb_get_property_value_length(wmNameReply) > 0) {
            QString title = QString::fromLatin1(
                reinterpret_cast<const char*>(xcb_get_property_value(wmNameReply)),
                xcb_get_property_value_length(wmNameReply)
            );
            client->updateTitle(title);
            std::free(wmNameReply);
        } else if (wmNameReply) {
            std::free(wmNameReply);
        }
    }

    // Query WM_CLASS
    auto classCookie = xcb_get_property(m_conn, 0, win, m_wmClassAtom, XCB_ATOM_STRING, 0, 1024);
    auto* classReply = xcb_get_property_reply(m_conn, classCookie, nullptr);
    if (classReply && xcb_get_property_value_length(classReply) > 0) {
        const char* val = reinterpret_cast<const char*>(xcb_get_property_value(classReply));
        int len = xcb_get_property_value_length(classReply);
        QString wmClass = QString::fromLatin1(val, len);
        client->updateWmClass(wmClass);
        std::free(classReply);
    } else if (classReply) {
        std::free(classReply);
    }
}

static void sendButtonPressRecursively(xcb_connection_t* conn, xcb_window_t win, xcb_button_press_event_t ev) {
    ev.event = win;
    xcb_send_event(conn, 0, win, XCB_EVENT_MASK_NO_EVENT, reinterpret_cast<const char*>(&ev));
    xcb_send_event(conn, 0, win, XCB_EVENT_MASK_BUTTON_PRESS, reinterpret_cast<const char*>(&ev));

    auto treeCookie = xcb_query_tree(conn, win);
    auto* treeReply = xcb_query_tree_reply(conn, treeCookie, nullptr);
    if (treeReply) {
        int numChildren = xcb_query_tree_children_length(treeReply);
        xcb_window_t* children = xcb_query_tree_children(treeReply);
        for (int i = 0; i < numChildren; ++i) {
            sendButtonPressRecursively(conn, children[i], ev);
        }
        std::free(treeReply);
    }
}

static void sendButtonReleaseRecursively(xcb_connection_t* conn, xcb_window_t win, xcb_button_release_event_t ev) {
    ev.event = win;
    xcb_send_event(conn, 0, win, XCB_EVENT_MASK_NO_EVENT, reinterpret_cast<const char*>(&ev));
    xcb_send_event(conn, 0, win, XCB_EVENT_MASK_BUTTON_RELEASE, reinterpret_cast<const char*>(&ev));

    auto treeCookie = xcb_query_tree(conn, win);
    auto* treeReply = xcb_query_tree_reply(conn, treeCookie, nullptr);
    if (treeReply) {
        int numChildren = xcb_query_tree_children_length(treeReply);
        xcb_window_t* children = xcb_query_tree_children(treeReply);
        for (int i = 0; i < numChildren; ++i) {
            sendButtonReleaseRecursively(conn, children[i], ev);
        }
        std::free(treeReply);
    }
}

void XEmbedService::sendClick(quint32 winId, int button, int x, int y, int globalX, int globalY) {
    if (!m_conn || winId == XCB_NONE) return;

    qCDebug(lcXEmbed) << "sendClick winId:" << winId << "button:" << button << "pos:" << x << y << "global:" << globalX << globalY << "hasXTest:" << m_hasXTest;

    if (globalX != 0 || globalY != 0) {
        uint32_t mgrPos[4] = {
            static_cast<uint32_t>(globalX),
            static_cast<uint32_t>(globalY),
            64,
            64
        };
        xcb_configure_window(m_conn, m_managerWin, XCB_CONFIG_WINDOW_X | XCB_CONFIG_WINDOW_Y | XCB_CONFIG_WINDOW_WIDTH | XCB_CONFIG_WINDOW_HEIGHT, mgrPos);

        uint32_t clientPos[4] = { 0, 0, 24, 24 };
        xcb_configure_window(m_conn, winId, XCB_CONFIG_WINDOW_X | XCB_CONFIG_WINDOW_Y | XCB_CONFIG_WINDOW_WIDTH | XCB_CONFIG_WINDOW_HEIGHT, clientPos);
    }

    // Enable input shape on manager window and stack ABOVE
    xcb_rectangle_t rect = { 0, 0, 64, 64 };
    xcb_shape_rectangles(m_conn, XCB_SHAPE_SO_SET, XCB_SHAPE_SK_INPUT, 0, m_managerWin, 0, 0, 1, &rect);
    const uint32_t stackAbove[1] = { XCB_STACK_MODE_ABOVE };
    xcb_configure_window(m_conn, m_managerWin, XCB_CONFIG_WINDOW_STACK_MODE, stackAbove);

    // Warp X11 pointer directly into the client window at the click coordinates
    xcb_warp_pointer(m_conn, XCB_NONE, winId, 0, 0, 0, 0, static_cast<int16_t>(x), static_cast<int16_t>(y));
    xcb_flush(m_conn);

    if (m_hasXTest) {
        xcb_test_fake_input(m_conn, XCB_BUTTON_PRESS, static_cast<uint8_t>(button), XCB_CURRENT_TIME, XCB_NONE, 0, 0, 0);
        xcb_flush(m_conn);
    } else {
        xcb_button_press_event_t ev;
        std::memset(&ev, 0, sizeof(ev));
        ev.response_type = XCB_BUTTON_PRESS;
        ev.event = winId;
        ev.child = XCB_NONE;
        ev.root = m_root;
        ev.root_x = static_cast<int16_t>(globalX + x);
        ev.root_y = static_cast<int16_t>(globalY + y);
        ev.event_x = static_cast<int16_t>(x);
        ev.event_y = static_cast<int16_t>(y);
        ev.detail = static_cast<xcb_button_t>(button);
        ev.state = 0;
        ev.time = XCB_CURRENT_TIME;
        ev.same_screen = 1;

        sendButtonPressRecursively(m_conn, winId, ev);
        xcb_flush(m_conn);
    }
}

void XEmbedService::sendRelease(quint32 winId, int button, int x, int y, int globalX, int globalY) {
    if (!m_conn || winId == XCB_NONE) return;

    qCDebug(lcXEmbed) << "sendRelease winId:" << winId << "button:" << button;

    if (m_hasXTest) {
        xcb_test_fake_input(m_conn, XCB_BUTTON_RELEASE, static_cast<uint8_t>(button), XCB_CURRENT_TIME, XCB_NONE, 0, 0, 0);
        xcb_flush(m_conn);
    } else {
        xcb_button_release_event_t ev;
        std::memset(&ev, 0, sizeof(ev));
        ev.response_type = XCB_BUTTON_RELEASE;
        ev.event = winId;
        ev.child = XCB_NONE;
        ev.root = m_root;
        ev.root_x = static_cast<int16_t>(globalX + x);
        ev.root_y = static_cast<int16_t>(globalY + y);
        ev.event_x = static_cast<int16_t>(x);
        ev.event_y = static_cast<int16_t>(y);
        ev.detail = static_cast<xcb_button_t>(button);
        ev.state = (button == 1 ? XCB_BUTTON_MASK_1 : (button == 2 ? XCB_BUTTON_MASK_2 : XCB_BUTTON_MASK_3));
        ev.time = XCB_CURRENT_TIME;
        ev.same_screen = 1;

        sendButtonReleaseRecursively(m_conn, winId, ev);
        xcb_flush(m_conn);
    }

    // Deactivate input region after a slight delay so popup menus can open and grab the pointer
    QTimer::singleShot(350, this, [this]() {
        if (!m_conn || m_managerWin == XCB_NONE) return;
        xcb_rectangle_t nullRect = { 0, 0, 0, 0 };
        xcb_shape_rectangles(m_conn, XCB_SHAPE_SO_SET, XCB_SHAPE_SK_INPUT, 0, m_managerWin, 0, 0, 1, &nullRect);
        const uint32_t stackBelow[1] = { XCB_STACK_MODE_BELOW };
        xcb_configure_window(m_conn, m_managerWin, XCB_CONFIG_WINDOW_STACK_MODE, stackBelow);
        xcb_flush(m_conn);
    });
}

void XEmbedService::sendMotion(quint32 winId, int x, int y, int globalX, int globalY) {
    if (!m_conn || winId == XCB_NONE) return;

    if (m_hasXTest) {
        xcb_test_fake_input(m_conn, XCB_MOTION_NOTIFY, 0, XCB_CURRENT_TIME, m_root, static_cast<int16_t>(globalX + x), static_cast<int16_t>(globalY + y), 0);
    } else {
        xcb_motion_notify_event_t ev;
        std::memset(&ev, 0, sizeof(ev));
        ev.response_type = XCB_MOTION_NOTIFY;
        ev.event = winId;
        ev.child = XCB_NONE;
        ev.root = m_root;
        ev.root_x = static_cast<int16_t>(globalX + x);
        ev.root_y = static_cast<int16_t>(globalY + y);
        ev.event_x = static_cast<int16_t>(x);
        ev.event_y = static_cast<int16_t>(y);
        ev.detail = 0;
        ev.state = 0;
        ev.time = XCB_CURRENT_TIME;
        ev.same_screen = 1;
        xcb_send_event(m_conn, 1, winId, XCB_EVENT_MASK_POINTER_MOTION, reinterpret_cast<const char*>(&ev));
    }
    xcb_flush(m_conn);
}

void XEmbedService::sendWheel(quint32 winId, int delta, int x, int y, int globalX, int globalY) {
    int button = (delta > 0) ? 4 : 5;
    sendClick(winId, button, x, y, globalX, globalY);
    sendRelease(winId, button, x, y, globalX, globalY);
}

} // namespace caelestia::services

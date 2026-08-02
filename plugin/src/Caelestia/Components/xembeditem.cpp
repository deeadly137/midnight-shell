#include "xembeditem.hpp"
#include "../Services/xembedservice.hpp"

#include <qpainter.h>
#include <qquickwindow.h>
#include <qtimer.h>
#include <qloggingcategory.h>
#include <xcb/xcb_image.h>
#include <xcb/composite.h>

Q_LOGGING_CATEGORY(lcXEmbedItem, "caelestia.components.xembeditem")

namespace caelestia::controls {

XEmbedItem::XEmbedItem(QQuickItem* parent)
    : QQuickPaintedItem(parent) {
    setRenderTarget(QQuickPaintedItem::Image);
    setAcceptedMouseButtons(Qt::AllButtons);
    setAcceptHoverEvents(true);
    setAntialiasing(true);
    setSmooth(true);
}

XEmbedItem::~XEmbedItem() {
    releaseClientWindow();
}

void XEmbedItem::setWindowId(quint32 id) {
    if (m_windowId == id) return;

    releaseClientWindow();
    m_windowId = id;
    emit windowIdChanged();

    if (m_windowId != 0) {
        setupClientWindow();
    }
}

void XEmbedItem::setupClientWindow() {
    auto* service = services::XEmbedService::instance();
    if (!service || !service->connection()) {
        return;
    }

    xcb_connection_t* conn = service->connection();

    // Query geometry
    auto geomCookie = xcb_get_geometry(conn, m_windowId);
    auto* geom = xcb_get_geometry_reply(conn, geomCookie, nullptr);
    if (!geom) {
        qCWarning(lcXEmbedItem) << "Failed to get geometry for window" << m_windowId;
        return;
    }

    m_clientWidth = geom->width > 0 ? geom->width : 24;
    m_clientHeight = geom->height > 0 ? geom->height : 24;
    std::free(geom);
    emit clientSizeChanged();

    // Redirect window with XComposite
    xcb_composite_redirect_window(conn, m_windowId, XCB_COMPOSITE_REDIRECT_MANUAL);

    // Create damage tracking
    m_damage = xcb_generate_id(conn);
    xcb_damage_create(conn, m_damage, m_windowId, XCB_DAMAGE_REPORT_LEVEL_NON_EMPTY);
    xcb_flush(conn);

    connect(service, &services::XEmbedService::damageReceived, this, &XEmbedItem::onDamageReceived);
    connect(service, &services::XEmbedService::windowDestroyed, this, &XEmbedItem::onWindowDestroyed);

    m_isValid = true;
    emit isValidChanged();

    updateImage();
    QTimer::singleShot(50, this, &XEmbedItem::updateImage);
    QTimer::singleShot(150, this, &XEmbedItem::updateImage);
    QTimer::singleShot(300, this, &XEmbedItem::updateImage);
}

void XEmbedItem::releaseClientWindow() {
    auto* service = services::XEmbedService::instance();
    if (service && service->connection() && m_windowId != 0) {
        xcb_connection_t* conn = service->connection();
        if (m_damage != XCB_NONE) {
            xcb_damage_destroy(conn, m_damage);
            m_damage = XCB_NONE;
        }
        xcb_composite_unredirect_window(conn, m_windowId, XCB_COMPOSITE_REDIRECT_MANUAL);
        xcb_flush(conn);

        disconnect(service, &services::XEmbedService::damageReceived, this, &XEmbedItem::onDamageReceived);
        disconnect(service, &services::XEmbedService::windowDestroyed, this, &XEmbedItem::onWindowDestroyed);
    }

    m_isValid = false;
    m_image = QImage();
    emit isValidChanged();
    update();
}

void XEmbedItem::updateImage() {
    auto* service = services::XEmbedService::instance();
    if (!service || !service->connection() || m_windowId == 0) {
        return;
    }

    xcb_connection_t* conn = service->connection();

    auto geomCookie = xcb_get_geometry(conn, m_windowId);
    auto* geom = xcb_get_geometry_reply(conn, geomCookie, nullptr);
    if (!geom) {
        return;
    }

    int width = geom->width;
    int height = geom->height;
    uint8_t depth = geom->depth;
    std::free(geom);

    if (width <= 0 || height <= 0) {
        return;
    }

    if (m_clientWidth != width || m_clientHeight != height) {
        m_clientWidth = width;
        m_clientHeight = height;
        emit clientSizeChanged();
    }

    xcb_pixmap_t pix = xcb_generate_id(conn);
    xcb_void_cookie_t nameCookie = xcb_composite_name_window_pixmap_checked(conn, m_windowId, pix);
    auto* nameErr = xcb_request_check(conn, nameCookie);

    xcb_drawable_t drawable = (nameErr == nullptr) ? pix : m_windowId;
    if (nameErr) {
        std::free(nameErr);
    }

    xcb_image_t* ximg = xcb_image_get(
        conn, drawable, 0, 0,
        static_cast<uint16_t>(width), static_cast<uint16_t>(height),
        0xFFFFFFFFU, XCB_IMAGE_FORMAT_Z_PIXMAP
    );

    if (drawable != m_windowId) {
        xcb_free_pixmap(conn, pix);
    }

    if (!ximg) {
        return;
    }

    QImage::Format format = QImage::Format_ARGB32_Premultiplied;
    if (depth == 24) {
        format = QImage::Format_RGB32;
    } else if (depth == 16) {
        format = QImage::Format_RGB16;
    }

    QImage img(
        reinterpret_cast<const uchar*>(ximg->data),
        ximg->width, ximg->height,
        static_cast<qsizetype>(ximg->stride),
        format
    );
    m_image = img.copy();

    xcb_image_destroy(ximg);

    update();
}

void XEmbedItem::onDamageReceived(quint32 winId) {
    if (winId == m_windowId) {
        updateImage();
    }
}

void XEmbedItem::onWindowDestroyed(quint32 winId) {
    if (winId == m_windowId) {
        releaseClientWindow();
    }
}

void XEmbedItem::paint(QPainter* painter) {
    if (!m_isValid || m_image.isNull()) {
        return;
    }

    painter->setRenderHint(QPainter::SmoothPixmapTransform, true);
    painter->setRenderHint(QPainter::Antialiasing, true);

    QRectF targetRect(0, 0, width(), height());
    painter->drawImage(targetRect, m_image);
}

QPoint XEmbedItem::mapToClientCoords(const QPointF& pos) const {
    if (width() <= 0 || height() <= 0 || m_clientWidth <= 0 || m_clientHeight <= 0) {
        return QPoint(0, 0);
    }
    int cx = static_cast<int>(pos.x() * (static_cast<qreal>(m_clientWidth) / width()));
    int cy = static_cast<int>(pos.y() * (static_cast<qreal>(m_clientHeight) / height()));
    return QPoint(cx, cy);
}

void XEmbedItem::mousePressEvent(QMouseEvent* event) {
    auto* service = services::XEmbedService::instance();
    qCDebug(lcXEmbedItem) << "mousePressEvent winId:" << m_windowId << "btn:" << event->button() << "pos:" << event->position();
    if (!service || m_windowId == 0) {
        QQuickPaintedItem::mousePressEvent(event);
        return;
    }

    int button = 1;
    if (event->button() == Qt::MiddleButton) button = 2;
    else if (event->button() == Qt::RightButton) button = 3;

    qreal dpr = window() ? window()->devicePixelRatio() : 1.0;
    QPoint pt = mapToClientCoords(event->position());
    QPointF origin = mapToGlobal(QPointF(0, 0));
    int gx = static_cast<int>(std::round(origin.x() * dpr));
    int gy = static_cast<int>(std::round(origin.y() * dpr));

    service->sendClick(m_windowId, button, pt.x(), pt.y(), gx, gy);
    event->accept();
}

void XEmbedItem::mouseReleaseEvent(QMouseEvent* event) {
    auto* service = services::XEmbedService::instance();
    qCDebug(lcXEmbedItem) << "mouseReleaseEvent winId:" << m_windowId << "btn:" << event->button() << "pos:" << event->position();
    if (!service || m_windowId == 0) {
        QQuickPaintedItem::mouseReleaseEvent(event);
        return;
    }

    int button = 1;
    if (event->button() == Qt::MiddleButton) button = 2;
    else if (event->button() == Qt::RightButton) button = 3;

    qreal dpr = window() ? window()->devicePixelRatio() : 1.0;
    QPoint pt = mapToClientCoords(event->position());
    QPointF origin = mapToGlobal(QPointF(0, 0));
    int gx = static_cast<int>(std::round(origin.x() * dpr));
    int gy = static_cast<int>(std::round(origin.y() * dpr));

    service->sendRelease(m_windowId, button, pt.x(), pt.y(), gx, gy);
    event->accept();
}

void XEmbedItem::hoverMoveEvent(QHoverEvent* event) {
    auto* service = services::XEmbedService::instance();
    if (service && m_windowId != 0) {
        qreal dpr = window() ? window()->devicePixelRatio() : 1.0;
        QPoint pt = mapToClientCoords(event->position());
        QPointF origin = mapToGlobal(QPointF(0, 0));
        int gx = static_cast<int>(std::round(origin.x() * dpr));
        int gy = static_cast<int>(std::round(origin.y() * dpr));
        service->sendMotion(m_windowId, pt.x(), pt.y(), gx, gy);
    }
    QQuickPaintedItem::hoverMoveEvent(event);
}

void XEmbedItem::wheelEvent(QWheelEvent* event) {
    auto* service = services::XEmbedService::instance();
    if (service && m_windowId != 0) {
        qreal dpr = window() ? window()->devicePixelRatio() : 1.0;
        QPoint pt = mapToClientCoords(event->position());
        int delta = event->angleDelta().y();
        QPointF origin = mapToGlobal(QPointF(0, 0));
        int gx = static_cast<int>(std::round(origin.x() * dpr));
        int gy = static_cast<int>(std::round(origin.y() * dpr));
        service->sendWheel(m_windowId, delta, pt.x(), pt.y(), gx, gy);
        event->accept();
    } else {
        QQuickPaintedItem::wheelEvent(event);
    }
}

void XEmbedItem::geometryChange(const QRectF& newGeometry, const QRectF& oldGeometry) {
    QQuickPaintedItem::geometryChange(newGeometry, oldGeometry);
    if (newGeometry.size() != oldGeometry.size()) {
        update();
    }
}

} // namespace caelestia::controls

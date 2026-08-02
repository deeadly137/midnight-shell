#pragma once

#include <qqmlintegration.h>
#include <qquickpainteditem.h>
#include <qimage.h>

#include <xcb/xcb.h>
#include <xcb/composite.h>
#include <xcb/damage.h>

namespace caelestia::controls {

class XEmbedItem : public QQuickPaintedItem {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(quint32 windowId READ windowId WRITE setWindowId NOTIFY windowIdChanged FINAL)
    Q_PROPERTY(bool isValid READ isValid NOTIFY isValidChanged FINAL)
    Q_PROPERTY(int clientWidth READ clientWidth NOTIFY clientSizeChanged FINAL)
    Q_PROPERTY(int clientHeight READ clientHeight NOTIFY clientSizeChanged FINAL)

public:
    explicit XEmbedItem(QQuickItem* parent = nullptr);
    ~XEmbedItem() override;

    [[nodiscard]] quint32 windowId() const { return m_windowId; }
    void setWindowId(quint32 id);

    [[nodiscard]] bool isValid() const { return m_isValid; }
    [[nodiscard]] int clientWidth() const { return m_clientWidth; }
    [[nodiscard]] int clientHeight() const { return m_clientHeight; }

    void paint(QPainter* painter) override;

signals:
    void windowIdChanged();
    void isValidChanged();
    void clientSizeChanged();

protected:
    void mousePressEvent(QMouseEvent* event) override;
    void mouseReleaseEvent(QMouseEvent* event) override;
    void hoverMoveEvent(QHoverEvent* event) override;
    void wheelEvent(QWheelEvent* event) override;
    void geometryChange(const QRectF& newGeometry, const QRectF& oldGeometry) override;

private slots:
    void onDamageReceived(quint32 winId);
    void onWindowDestroyed(quint32 winId);

private:
    void setupClientWindow();
    void releaseClientWindow();
    void updateImage();
    QPoint mapToClientCoords(const QPointF& pos) const;

    quint32 m_windowId = 0;
    bool m_isValid = false;
    int m_clientWidth = 24;
    int m_clientHeight = 24;
    xcb_damage_damage_t m_damage = XCB_NONE;
    QImage m_image;
};

} // namespace caelestia::controls

#pragma once

#include <QQuickImageProvider>

namespace zinc::ui {

class AttachmentImageProvider : public QQuickImageProvider {
public:
    AttachmentImageProvider();

    QImage requestImage(const QString& id, QSize* size, const QSize& requestedSize) override;
};

} // namespace zinc::ui


#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QtQml/qqml.h>

class QJSEngine;

namespace zinc::ui {

class FeatureFlags : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool qrEnabled READ qrEnabled CONSTANT)

public:
    explicit FeatureFlags(QObject* parent = nullptr)
        : QObject(parent) {}

    static QObject* create(QQmlEngine* engine, QJSEngine* script_engine);

    [[nodiscard]] bool qrEnabled() const;
};

} // namespace zinc::ui

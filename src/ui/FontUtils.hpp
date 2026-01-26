#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QJSEngine>
#include <QtQml/qqml.h>

namespace zinc::ui {

class FontUtils : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit FontUtils(QObject* parent = nullptr);

    static FontUtils* create(QQmlEngine* engine, QJSEngine*) {
        static FontUtils instance;
        engine->setObjectOwnership(&instance, QQmlEngine::CppOwnership);
        return &instance;
    }

    Q_INVOKABLE QStringList systemFontFamilies() const;
};

} // namespace zinc::ui

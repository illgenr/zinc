#include "ui/Clipboard.hpp"

#include <QClipboard>
#include <QGuiApplication>

namespace zinc::ui {

Clipboard::Clipboard(QObject* parent)
    : QObject(parent) {
}

QString Clipboard::text() const {
    if (auto* clipboard = QGuiApplication::clipboard()) {
        return clipboard->text();
    }
    return {};
}

void Clipboard::setText(const QString& text) {
    if (auto* clipboard = QGuiApplication::clipboard()) {
        clipboard->setText(text);
    }
}

} // namespace zinc::ui


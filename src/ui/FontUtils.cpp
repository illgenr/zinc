#include "ui/FontUtils.hpp"

#include <QFontDatabase>

namespace zinc::ui {

FontUtils::FontUtils(QObject* parent)
    : QObject(parent) {}

QStringList FontUtils::systemFontFamilies() const {
    return QFontDatabase::families();
}

} // namespace zinc::ui


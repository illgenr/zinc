#include "ui/FeatureFlags.hpp"

namespace zinc::ui {

QObject* FeatureFlags::create(QQmlEngine* engine, QJSEngine* script_engine) {
    Q_UNUSED(engine)
    Q_UNUSED(script_engine)
    return new FeatureFlags();
}

bool FeatureFlags::qrEnabled() const {
#ifdef ZINC_ENABLE_QR
    return ZINC_ENABLE_QR != 0;
#else
    return false;
#endif
}

} // namespace zinc::ui

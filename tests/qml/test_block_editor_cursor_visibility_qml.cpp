#include <catch2/catch_test_macros.hpp>
#include <catch2/catch_approx.hpp>

#include <QQmlComponent>
#include <QQmlEngine>
#include <QQmlError>
#include <QStringList>
#include <QUrl>
#include <memory>

#include "ui/qml_types.hpp"

namespace {

void registerTypesOnce() {
    static bool registered = false;
    if (registered) {
        return;
    }
    zinc::ui::registerQmlTypes();
    registered = true;
}

QString formatErrors(const QList<QQmlError>& errors) {
    QStringList lines;
    lines.reserve(errors.size());
    for (const auto& error : errors) {
        lines.append(error.toString());
    }
    return lines.join('\n');
}

} // namespace

TEST_CASE("QML: ScrollMath computes cursor reveal scroll", "[qml]") {
    registerTypesOnce();

    QQmlEngine engine;
    QQmlComponent component(&engine);
    component.setData(
        "import QtQml\n"
        "import \"qrc:/qt/qml/zinc/qml/components/ScrollMath.js\" as ScrollMath\n"
        "QtObject {\n"
            "    objectName: \"host\"\n"
            "    property real outDown: ScrollMath.contentYToRevealRegion(100, 380, 420, 300, 16, 16)\n"
            "    property real outUp: ScrollMath.contentYToRevealRegion(200, 150, 170, 300, 16, 16)\n"
            "    property real outNoop: ScrollMath.contentYToRevealRegion(100, 150, 170, 300, 16, 16)\n"
            "    property real outCenter: ScrollMath.contentYToPlaceRegionCenter(380, 420, 150)\n"
        "}\n",
        QUrl(QStringLiteral("qrc:/qt/qml/zinc/tests/BlockEditorScrollMathHost.qml")));

    if (component.status() == QQmlComponent::Error) {
        FAIL(formatErrors(component.errors()).toStdString());
    }
    REQUIRE(component.status() == QQmlComponent::Ready);

    std::unique_ptr<QObject> root(component.create());
    REQUIRE(root);

    REQUIRE(root->property("outDown").toDouble() == Catch::Approx(136.0));
    REQUIRE(root->property("outUp").toDouble() == Catch::Approx(134.0));
    REQUIRE(root->property("outNoop").toDouble() == Catch::Approx(100.0));
    REQUIRE(root->property("outCenter").toDouble() == Catch::Approx(250.0));
}

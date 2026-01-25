// Pure logic for when to force-show the cursor indicator while navigating.
.pragma library

function shouldArm(modifiers, key) {
    const hasNavigationModifier =
        (modifiers & Qt.ControlModifier) ||
        (modifiers & Qt.AltModifier) ||
        (modifiers & Qt.MetaModifier)

    if (hasNavigationModifier) return false

    return key === Qt.Key_Up ||
        key === Qt.Key_Down ||
        key === Qt.Key_Left ||
        key === Qt.Key_Right
}


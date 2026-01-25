// Shared pure logic used by BlockEditor for Enter-key behavior.
.pragma library

function enterAction(params) {
    const blockIndex = params && ("blockIndex" in params) ? params.blockIndex : -1
    const cursorPos = params && ("cursorPos" in params) ? params.cursorPos : -1
    const blockType = params && ("blockType" in params) ? (params.blockType || "paragraph") : "paragraph"
    const content = params && ("content" in params) ? (params.content || "") : ""

    if (blockIndex < 0) {
        return { kind: "noop" }
    }

    if (blockType === "todo" && content.length === 0) {
        return { kind: "convertTodoToParagraph" }
    }

    const insertAbove = cursorPos === 0 && content.length > 0
    const insertIndex = insertAbove ? blockIndex : (blockIndex + 1)
    const newBlockType = (blockType === "todo") ? "todo" : "paragraph"

    return {
        kind: "insert",
        insertIndex: insertIndex,
        newBlockType: newBlockType,
        focusCursorPos: 0,
    }
}

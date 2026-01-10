import QtQuick

/**
 * QRCodeImage - Renders a QR code from data string using Canvas.
 * 
 * This generates a visual QR-like pattern that includes standard finder patterns.
 * For a production app with actual QR scanning, use a proper QR library.
 */
Canvas {
    id: root

    property string data: ""
    property color foregroundColor: "#000000"
    property color backgroundColor: "#ffffff"
    property int moduleCount: 25  // QR Version 2

    // Ensure canvas has size before painting
    width: 200
    height: 200
    
    // Request repaint on property changes
    onDataChanged: { markDirty(); requestPaint() }
    onForegroundColorChanged: { markDirty(); requestPaint() }
    onBackgroundColorChanged: { markDirty(); requestPaint() }
    onWidthChanged: { markDirty(); requestPaint() }
    onHeightChanged: { markDirty(); requestPaint() }

    // Mark canvas as needing full redraw
    function markDirty() {
        if (available) {
            var ctx = getContext("2d")
            if (ctx) {
                ctx.reset()
            }
        }
    }

    // Ensure painting happens after component is ready
    Component.onCompleted: {
        if (available) {
            requestPaint()
        }
    }

    onAvailableChanged: {
        if (available) {
            requestPaint()
        }
    }

    onPaint: {
        if (!available) {
            return
        }
        
        var ctx = getContext("2d")
        if (!ctx) {
            return
        }

        // Clear canvas with background color
        ctx.fillStyle = backgroundColor
        ctx.fillRect(0, 0, width, height)

        // If no data, draw placeholder
        if (!data || data.length === 0) {
            drawPlaceholder(ctx)
            return
        }

        // Generate and draw QR matrix
        var matrix = generateQRMatrix(data)
        if (!matrix || matrix.length === 0) {
            drawPlaceholder(ctx)
            return
        }

        drawMatrix(ctx, matrix)
    }

    function drawPlaceholder(ctx) {
        ctx.fillStyle = foregroundColor
        ctx.font = "bold 24px sans-serif"
        ctx.textAlign = "center"
        ctx.textBaseline = "middle"
        ctx.fillText("QR", width / 2, height / 2)
    }

    function drawMatrix(ctx, matrix) {
        var modules = matrix.length
        var padding = 2
        var cellSize = Math.floor(Math.min(width, height) / (modules + padding * 2))
        var totalSize = cellSize * modules
        var offsetX = Math.floor((width - totalSize) / 2)
        var offsetY = Math.floor((height - totalSize) / 2)

        ctx.fillStyle = foregroundColor
        
        for (var y = 0; y < modules; y++) {
            for (var x = 0; x < modules; x++) {
                if (matrix[y][x]) {
                    ctx.fillRect(
                        offsetX + x * cellSize,
                        offsetY + y * cellSize,
                        cellSize,
                        cellSize
                    )
                }
            }
        }
    }

    // Generate QR code matrix
    function generateQRMatrix(text) {
        if (!text || text.length === 0) return null

        var size = moduleCount
        var matrix = []

        // Initialize matrix with false
        for (var y = 0; y < size; y++) {
            matrix[y] = []
            for (var x = 0; x < size; x++) {
                matrix[y][x] = false
            }
        }

        // Add finder patterns (3 corners)
        addFinderPattern(matrix, 0, 0)
        addFinderPattern(matrix, size - 7, 0)
        addFinderPattern(matrix, 0, size - 7)

        // Add separators around finder patterns
        addSeparators(matrix, size)

        // Add timing patterns
        addTimingPatterns(matrix, size)

        // Add alignment pattern for version 2+
        if (size >= 25) {
            addAlignmentPattern(matrix, size - 9, size - 9)
        }

        // Add format information areas
        addFormatInfo(matrix, size)

        // Encode data into remaining cells
        encodeData(matrix, text, size)

        return matrix
    }

    function addFinderPattern(matrix, startX, startY) {
        // 7x7 finder pattern: outer black, inner white, center black
        for (var y = 0; y < 7; y++) {
            for (var x = 0; x < 7; x++) {
                var isOuter = (x === 0 || x === 6 || y === 0 || y === 6)
                var isInner = (x >= 2 && x <= 4 && y >= 2 && y <= 4)
                matrix[startY + y][startX + x] = isOuter || isInner
            }
        }
    }

    function addSeparators(matrix, size) {
        // White separators around finder patterns
        // Top-left
        for (var i = 0; i < 8; i++) {
            if (i < size) {
                matrix[7][i] = false
                matrix[i][7] = false
            }
        }
        // Top-right
        for (var i = 0; i < 8; i++) {
            if (size - 8 + i < size) {
                matrix[7][size - 8 + i] = false
            }
            if (i < 8) {
                matrix[i][size - 8] = false
            }
        }
        // Bottom-left
        for (var i = 0; i < 8; i++) {
            if (i < size) {
                matrix[size - 8][i] = false
            }
            if (size - 8 + i < size) {
                matrix[size - 8 + i][7] = false
            }
        }
    }

    function addTimingPatterns(matrix, size) {
        // Alternating black/white pattern
        for (var i = 8; i < size - 8; i++) {
            var isBlack = (i % 2 === 0)
            matrix[6][i] = isBlack
            matrix[i][6] = isBlack
        }
    }

    function addAlignmentPattern(matrix, centerX, centerY) {
        // 5x5 alignment pattern
        for (var y = -2; y <= 2; y++) {
            for (var x = -2; x <= 2; x++) {
                var px = centerX + x
                var py = centerY + y
                if (px >= 0 && px < matrix.length && py >= 0 && py < matrix.length) {
                    var isOuter = (Math.abs(x) === 2 || Math.abs(y) === 2)
                    var isCenter = (x === 0 && y === 0)
                    matrix[py][px] = isOuter || isCenter
                }
            }
        }
    }

    function addFormatInfo(matrix, size) {
        // Dark module (always present)
        matrix[size - 8][8] = true
    }

    function encodeData(matrix, text, size) {
        // Hash the text to create deterministic pattern
        var hash = hashString(text)
        
        // Find available data cells
        var dataCells = []
        for (var y = 0; y < size; y++) {
            for (var x = 0; x < size; x++) {
                if (isDataCell(x, y, size)) {
                    dataCells.push({x: x, y: y})
                }
            }
        }

        // Convert text to bits
        var bits = textToBits(text)
        
        // Fill data cells with encoded bits + mask
        for (var i = 0; i < dataCells.length; i++) {
            var cell = dataCells[i]
            var bit = (i < bits.length) ? bits[i] : ((hash >> (i % 31)) & 1)
            // Apply mask pattern 0: (x + y) % 2 == 0
            var mask = ((cell.x + cell.y) % 2 === 0) ? 1 : 0
            matrix[cell.y][cell.x] = ((bit ^ mask) === 1)
        }
    }

    function isDataCell(x, y, size) {
        // Exclude finder patterns and separators
        if (x < 9 && y < 9) return false  // Top-left
        if (x >= size - 8 && y < 9) return false  // Top-right
        if (x < 9 && y >= size - 8) return false  // Bottom-left
        
        // Exclude timing patterns
        if (x === 6 || y === 6) return false
        
        // Exclude alignment pattern area
        if (x >= size - 11 && x <= size - 7 && y >= size - 11 && y <= size - 7) return false
        
        return true
    }

    function hashString(str) {
        var hash = 5381
        for (var i = 0; i < str.length; i++) {
            hash = ((hash << 5) + hash) + str.charCodeAt(i)
            hash = hash & 0x7FFFFFFF
        }
        return hash
    }

    function textToBits(text) {
        var bits = []
        // Mode indicator (byte mode = 0100)
        bits.push(0, 1, 0, 0)
        
        // Character count (8 bits for version 1-9)
        var len = Math.min(text.length, 255)
        for (var i = 7; i >= 0; i--) {
            bits.push((len >> i) & 1)
        }
        
        // Data bytes
        for (var i = 0; i < text.length; i++) {
            var charCode = text.charCodeAt(i)
            for (var j = 7; j >= 0; j--) {
                bits.push((charCode >> j) & 1)
            }
        }
        
        // Terminator
        bits.push(0, 0, 0, 0)
        
        return bits
    }
}

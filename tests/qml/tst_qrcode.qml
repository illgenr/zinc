import QtQuick
import QtTest

TestCase {
    id: testCase
    name: "QRCodeTests"
    when: windowShown

    width: 300
    height: 300

    // QR Code generation helper functions (same as in QRCodeImage)
    function simpleHash(str) {
        var hash = 0
        for (var i = 0; i < str.length; i++) {
            var charCode = str.charCodeAt(i)
            hash = ((hash << 5) - hash) + charCode
            hash = hash & hash
        }
        return Math.abs(hash)
    }

    function generateQRMatrix(text) {
        if (!text || text.length === 0) return null

        var size = 25
        var matrix = []

        // Initialize matrix
        for (var y = 0; y < size; y++) {
            matrix[y] = []
            for (var x = 0; x < size; x++) {
                matrix[y][x] = false
            }
        }

        // Add finder patterns
        addFinderPattern(matrix, 0, 0)
        addFinderPattern(matrix, size - 7, 0)
        addFinderPattern(matrix, 0, size - 7)

        return matrix
    }

    function addFinderPattern(matrix, startX, startY) {
        for (var i = 0; i < 7; i++) {
            matrix[startY][startX + i] = true
            matrix[startY + 6][startX + i] = true
            matrix[startY + i][startX] = true
            matrix[startY + i][startX + 6] = true
        }
        for (var y = 1; y < 6; y++) {
            for (var x = 1; x < 6; x++) {
                matrix[startY + y][startX + x] = false
            }
        }
        for (var y = 2; y < 5; y++) {
            for (var x = 2; x < 5; x++) {
                matrix[startY + y][startX + x] = true
            }
        }
    }

    function test_simpleHash_notEmpty() {
        var hash = simpleHash("test")
        verify(hash > 0, "Hash should be positive")
    }

    function test_simpleHash_different() {
        var hash1 = simpleHash("test1")
        var hash2 = simpleHash("test2")
        verify(hash1 !== hash2, "Different strings should have different hashes")
    }

    function test_simpleHash_consistent() {
        var hash1 = simpleHash("same")
        var hash2 = simpleHash("same")
        compare(hash1, hash2, "Same string should produce same hash")
    }

    function test_generateQRMatrix_null() {
        var matrix = generateQRMatrix("")
        compare(matrix, null, "Empty string should return null")
    }

    function test_generateQRMatrix_size() {
        var matrix = generateQRMatrix("test")
        compare(matrix.length, 25, "Matrix should be 25x25")
        compare(matrix[0].length, 25, "Matrix row should be 25 elements")
    }

    function test_finderPattern_topLeft() {
        var matrix = generateQRMatrix("test")
        // Top-left finder pattern should have corners true
        verify(matrix[0][0], "Top-left corner should be true")
        verify(matrix[0][6], "Top-left pattern right edge should be true")
        verify(matrix[6][0], "Top-left pattern bottom edge should be true")
        verify(matrix[6][6], "Top-left pattern bottom-right should be true")
    }

    function test_finderPattern_topRight() {
        var matrix = generateQRMatrix("test")
        // Top-right finder pattern
        verify(matrix[0][18], "Top-right pattern left edge should be true")
        verify(matrix[0][24], "Top-right corner should be true")
    }

    function test_finderPattern_bottomLeft() {
        var matrix = generateQRMatrix("test")
        // Bottom-left finder pattern
        verify(matrix[18][0], "Bottom-left pattern top edge should be true")
        verify(matrix[24][0], "Bottom-left corner should be true")
    }
}


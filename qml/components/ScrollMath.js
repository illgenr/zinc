.pragma library

function contentYToRevealRegion(currentY, regionTop, regionBottom, viewportHeight, topMargin, bottomMargin) {
    const vpTop = currentY + topMargin
    const vpBottom = currentY + Math.max(0, viewportHeight - bottomMargin)
    if (regionBottom > vpBottom) {
        return currentY + (regionBottom - vpBottom)
    }
    if (regionTop < vpTop) {
        return currentY - (vpTop - regionTop)
    }
    return currentY
}

function contentYToPlaceRegionCenter(regionTop, regionBottom, desiredCenterYInViewport) {
    const regionCenter = (regionTop + regionBottom) * 0.5
    return regionCenter - desiredCenterYInViewport
}

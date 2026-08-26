pragma Singleton
import Quickshell

Singleton {
    id: root

    function intersectionArea(regionA, regionB) {
        const interX1 = Math.max(regionA.at[0], regionB.at[0]);
        const interY1 = Math.max(regionA.at[1], regionB.at[1]);
        const interX2 = Math.min(regionA.at[0] + regionA.size[0], regionB.at[0] + regionB.size[0]);
        const interY2 = Math.min(regionA.at[1] + regionA.size[1], regionB.at[1] + regionB.size[1]);

        return Math.max(0, interX2 - interX1) * Math.max(0, interY2 - interY1);
    }

    function intersectionOverUnion(regionA, regionB) {
        const interArea = intersectionArea(regionA, regionB);
        const areaA = (regionA.size[0]) * (regionA.size[1]);
        const areaB = (regionB.size[0]) * (regionB.size[1]);
        const unionArea = areaA + areaB - interArea;

        return unionArea > 0 ? interArea / unionArea : 0;
    }

    function filterOverlappingImageRegions(regions) {
        let keep = [];
        let removed = new Set();
        for (let i = 0; i < regions.length; ++i) {
            if (removed.has(i)) continue;
            let regionA = regions[i];
            for (let j = i + 1; j < regions.length; ++j) {
                if (removed.has(j)) continue;
                let regionB = regions[j];
                if (intersectionOverUnion(regionA, regionB) > 0) {
                    // Compare areas
                    let areaA = regionA.size[0] * regionA.size[1];
                    let areaB = regionB.size[0] * regionB.size[1];
                    if (areaA <= areaB) {
                        removed.add(j);
                    } else {
                        removed.add(i);
                    }
                }
            }
        }
        for (let i = 0; i < regions.length; ++i) {
            if (!removed.has(i)) keep.push(regions[i]);
        }
        return keep;
    }

    function filterWindowRegionsByLayers(windowRegions, layerRegions, coverageThreshold = 0.5) {
        return windowRegions.filter(windowRegion => {
            const windowArea = windowRegion.size[0] * windowRegion.size[1];
            if (windowArea <= 0) return false;
            for (let i = 0; i < layerRegions.length; ++i) {
                if (intersectionArea(windowRegion, layerRegions[i]) / windowArea > coverageThreshold)
                    return false;
            }
            return true;
        });
    }

    function filterImageRegions(regions, windowRegions, threshold = 0.1) {
        // Remove image regions that overlap too much with any window region
        let filtered = regions.filter(region => {
            for (let i = 0; i < windowRegions.length; ++i) {
                if (intersectionOverUnion(region, windowRegions[i]) > threshold)
                    return false;
            }
            return true;
        });
        // Remove overlapping image regions, keep only the smaller one
        return filterOverlappingImageRegions(filtered);
    }
}

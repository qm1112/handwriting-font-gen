import paper from 'paper'

let paperScope = null

function getPaperScope() {
  if (!paperScope) {
    paperScope = new paper.PaperScope()
    const offscreenCanvas = document.createElement('canvas')
    offscreenCanvas.width = 1000
    offscreenCanvas.height = 1000
    paperScope.setup(offscreenCanvas)
  }
  return paperScope
}

function calcRadius(pressure, baseSize) {
  const p = typeof pressure === 'number' ? Math.max(0.05, Math.min(1, pressure)) : 0.5
  return (baseSize * (0.25 + p * 0.9)) / 2
}

/**
 * Sample quadratic Bezier midpoint-smoothed centerline with interpolated radii.
 */
function sampleSmoothedCenterline(rawPoints, baseSize) {
  const samples = []
  const n = rawPoints.length
  if (n === 0) return samples

  const pushSample = (x, y, r) => {
    if (samples.length > 0) {
      const prev = samples[samples.length - 1]
      const dx = x - prev.x
      const dy = y - prev.y
      if (dx * dx + dy * dy < 0.25) return
    }
    samples.push({ x, y, r })
  }

  let prevMidX = rawPoints[0][0]
  let prevMidY = rawPoints[0][1]
  let prevP = rawPoints[0][2] ?? 0.5
  pushSample(prevMidX, prevMidY, calcRadius(prevP, baseSize))

  for (let i = 1; i < n; i++) {
    const p1 = rawPoints[i - 1]
    const p2 = rawPoints[i]
    const midX = (p1[0] + p2[0]) / 2
    const midY = (p1[1] + p2[1]) / 2
    const p1Press = p1[2] ?? 0.5
    const p2Press = p2[2] ?? 0.5
    const midP = (p1Press + p2Press) / 2

    const segLen = Math.hypot(midX - prevMidX, midY - prevMidY)
    const steps = Math.max(2, Math.min(10, Math.ceil(segLen / 6)))

    for (let s = 1; s <= steps; s++) {
      const t = s / steps
      const mt = 1 - t
      const x = mt * mt * prevMidX + 2 * mt * t * p1[0] + t * t * midX
      const y = mt * mt * prevMidY + 2 * mt * t * p1[1] + t * t * midY
      const p = prevP + (midP - prevP) * t
      pushSample(x, y, calcRadius(p, baseSize))
    }

    prevMidX = midX
    prevMidY = midY
    prevP = midP
  }

  // Final segment to last point
  const last = rawPoints[n - 1]
  const lastP = last[2] ?? 0.5
  pushSample(last[0], last[1], calcRadius(lastP, baseSize))

  return samples
}

/**
 * Render a single raw stroke ([x, y, pressure][]) into a closed SVG path d string
 * using quadratic Bezier midpoint smoothing + normal offset + round endcaps.
 */
export function buildStrokePath(rawPoints, brushOptions) {
  if (!rawPoints || rawPoints.length === 0) return ''
  const baseSize = brushOptions?.size || 48

  if (rawPoints.length === 1) {
    const [x, y, p] = rawPoints[0]
    const r = calcRadius(p, baseSize)
    return `M${(x - r).toFixed(2)},${y.toFixed(2)} A${r.toFixed(2)},${r.toFixed(2)} 0 1 0 ${(x + r).toFixed(2)},${y.toFixed(2)} A${r.toFixed(2)},${r.toFixed(2)} 0 1 0 ${(x - r).toFixed(2)},${y.toFixed(2)} Z`
  }

  const samples = sampleSmoothedCenterline(rawPoints, baseSize)
  if (samples.length < 2) {
    const s = samples[0] || { x: rawPoints[0][0], y: rawPoints[0][1], r: calcRadius(rawPoints[0][2], baseSize) }
    return `M${(s.x - s.r).toFixed(2)},${s.y.toFixed(2)} A${s.r.toFixed(2)},${s.r.toFixed(2)} 0 1 0 ${(s.x + s.r).toFixed(2)},${s.y.toFixed(2)} A${s.r.toFixed(2)},${s.r.toFixed(2)} 0 1 0 ${(s.x - s.r).toFixed(2)},${s.y.toFixed(2)} Z`
  }

  const m = samples.length
  const leftPts = new Array(m)
  const rightPts = new Array(m)

  for (let i = 0; i < m; i++) {
    const prev = samples[Math.max(0, i - 1)]
    const next = samples[Math.min(m - 1, i + 1)]
    let tx = next.x - prev.x
    let ty = next.y - prev.y
    const len = Math.hypot(tx, ty) || 1
    tx /= len
    ty /= len

    const { x, y, r } = samples[i]
    leftPts[i] = [x - ty * r, y + tx * r]
    rightPts[i] = [x + ty * r, y - tx * r]
  }

  const rStart = samples[0].r
  const rEnd = samples[m - 1].r
  const CAP_STEPS = 8

  const thetaStart = Math.atan2(
    samples[1].y - samples[0].y,
    samples[1].x - samples[0].x
  )
  const thetaEnd = Math.atan2(
    samples[m - 1].y - samples[m - 2].y,
    samples[m - 1].x - samples[m - 2].x
  )

  let d = `M${leftPts[0][0].toFixed(2)},${leftPts[0][1].toFixed(2)}`
  for (let i = 1; i < m; i++) {
    d += ` L${leftPts[i][0].toFixed(2)},${leftPts[i][1].toFixed(2)}`
  }

  // End cap: from leftPts[m-1] (thetaEnd + PI/2) outward through thetaEnd to rightPts[m-1] (thetaEnd - PI/2)
  const endCenter = samples[m - 1]
  for (let s = 1; s < CAP_STEPS; s++) {
    const angle = thetaEnd + Math.PI / 2 - (Math.PI * s) / CAP_STEPS
    const px = endCenter.x + Math.cos(angle) * rEnd
    const py = endCenter.y + Math.sin(angle) * rEnd
    d += ` L${px.toFixed(2)},${py.toFixed(2)}`
  }
  d += ` L${rightPts[m - 1][0].toFixed(2)},${rightPts[m - 1][1].toFixed(2)}`

  for (let i = m - 2; i >= 0; i--) {
    d += ` L${rightPts[i][0].toFixed(2)},${rightPts[i][1].toFixed(2)}`
  }

  // Start cap: from rightPts[0] (thetaStart - PI/2) outward through thetaStart - PI to leftPts[0] (thetaStart - 3*PI/2)
  const startCenter = samples[0]
  for (let s = 1; s < CAP_STEPS; s++) {
    const angle = thetaStart - Math.PI / 2 - (Math.PI * s) / CAP_STEPS
    const px = startCenter.x + Math.cos(angle) * rStart
    const py = startCenter.y + Math.sin(angle) * rStart
    d += ` L${px.toFixed(2)},${py.toFixed(2)}`
  }
  d += ` Z`

  return d
}

/**
 * Perform boolean union (unite) across multiple closed SVG path strings using paper.js.
 * Eliminates self-intersection / stroke overlap cutouts and returns a single merged SVG path.
 */
export function uniteSvgPaths(pathStrings) {
  const validPaths = (pathStrings || []).filter((d) => typeof d === 'string' && d.trim().length > 0)
  if (validPaths.length === 0) return ''
  if (validPaths.length === 1) return validPaths[0]

  try {
    const scope = getPaperScope()
    scope.project.activeLayer.removeChildren()

    let unitedItem = null
    for (const d of validPaths) {
      const item = scope.project.importSVG(`<path d="${d}" />`, {
        expandShapes: true,
        insert: false,
      })
      if (!item) continue

      // Normalize to Path / CompoundPath
      const pathItem = item instanceof scope.PathItem ? item : item.firstChild
      if (!pathItem || !(pathItem instanceof scope.PathItem)) continue

      if (!unitedItem) {
        unitedItem = pathItem
      } else {
        const next = unitedItem.unite(pathItem, { insert: false })
        unitedItem.remove()
        pathItem.remove()
        unitedItem = next
      }
    }

    if (!unitedItem) {
      return validPaths.join(' ')
    }

    const pathData = unitedItem.pathData || ''
    unitedItem.remove()
    scope.project.activeLayer.removeChildren()
    return pathData || validPaths.join(' ')
  } catch (err) {
    console.warn('[paper.js unite] fallback to concatenated paths:', err)
    return validPaths.join(' ')
  }
}

<template>
  <div class="relative flex items-center justify-center w-full h-full">
    <div
      ref="canvasWrapper"
      class="writing-surface relative aspect-square w-full bg-white rounded-2xl shadow-2xl shadow-black/50 ring-1 ring-slate-700/60 overflow-hidden cursor-crosshair"
      :style="{ maxWidth: `calc(min(78vh, 680px) * ${scale / 100})` }"
      @pointerdown="handlePointerDown"
      @pointermove="handlePointerMove"
      @pointerup="handlePointerUp"
      @pointercancel="handlePointerUp"
      @pointerleave="handlePointerUp"
    >
      <!-- 1000x1000 Logical Coordinate SVG -->
      <svg
        viewBox="0 0 1000 1000"
        class="w-full h-full block pointer-events-none select-none"
      >
        <!-- Guide Lines: 米字格 / 九宫格 + 85% 安全边距虚线框 -->
        <g v-if="guideType !== 'none'" stroke="#cbd5e1" stroke-width="1.5" fill="none">
          <!-- Outer 85% Safe Margin Box (75..925) -->
          <rect
            x="75"
            y="75"
            width="850"
            height="850"
            stroke="#94a3b8"
            stroke-width="2"
            stroke-dasharray="10 8"
            opacity="0.7"
          />

          <!-- 米字格 -->
          <template v-if="guideType === 'mi'">
            <line x1="500" y1="0" x2="500" y2="1000" stroke-dasharray="8 8" />
            <line x1="0" y1="500" x2="1000" y2="500" stroke-dasharray="8 8" />
            <line x1="0" y1="0" x2="1000" y2="1000" stroke-dasharray="8 8" opacity="0.6" />
            <line x1="1000" y1="0" x2="0" y2="1000" stroke-dasharray="8 8" opacity="0.6" />
          </template>

          <!-- 九宫格 -->
          <template v-else-if="guideType === 'jiu'">
            <line x1="333.33" y1="0" x2="333.33" y2="1000" stroke-dasharray="8 8" />
            <line x1="666.67" y1="0" x2="666.67" y2="1000" stroke-dasharray="8 8" />
            <line x1="0" y1="333.33" x2="1000" y2="333.33" stroke-dasharray="8 8" />
            <line x1="0" y1="666.67" x2="1000" y2="666.67" stroke-dasharray="8 8" />
          </template>
        </g>

        <!-- Onion Skin Reference Character -->
        <text
          v-if="showOnionSkin && targetChar"
          x="500"
          y="535"
          text-anchor="middle"
          dominant-baseline="central"
          fill="#64748b"
          :style="{ fontFamily: onionFontFamily, fontSize: onionSize + 'px', opacity: onionOpacity }"
          class="select-none pointer-events-none"
        >
          {{ targetChar }}
        </text>

        <!-- Committed United Path (or individual strokes) -->
        <path
          v-if="mergedPath"
          :d="mergedPath"
          fill="#0f172a"
          fill-rule="nonzero"
        />
      </svg>

      <!-- High-frequency 2D Canvas overlay for active stroke (zero Vue reactivity overhead during pointermove) -->
      <canvas
        ref="activeCanvas"
        class="absolute inset-0 w-full h-full pointer-events-none select-none"
      />

      <!-- Apple Pencil Only Indicator -->
      <div
        v-if="pencilOnly"
        class="absolute top-3 right-3 px-2.5 py-1 rounded-full bg-indigo-500/15 border border-indigo-400/30 text-indigo-700 text-xs font-medium pointer-events-none"
      >
        仅 Apple Pencil
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, watch } from 'vue'
import { buildStrokePath, uniteSvgPaths } from '../utils/strokeUtils'
import { getFontFamily } from '../utils/fontMap'

const props = defineProps({
  targetChar: { type: String, default: '' },
  brushOptions: { type: Object, required: true },
  pencilOnly: { type: Boolean, default: false },
  guideType: { type: String, default: 'mi' }, // 'mi' | 'jiu' | 'none'
  showOnionSkin: { type: Boolean, default: true },
  onionFont: { type: String, default: 'kaiti' }, // 'kaiti' | 'heiti' | 'songti'
  onionSize: { type: Number, default: 760 },
  onionOpacity: { type: Number, default: 0.18 },
  scale: { type: Number, default: 100 },
})

const emit = defineEmits(['update:hasStrokes', 'stroke-end'])

const canvasWrapper = ref(null)
const activeCanvas = ref(null)
const strokes = ref([]) // Array of { points: [[x,y,p], ...], path: string }
let activePoints = []
const isDrawing = ref(false)
const activePointerId = ref(null)
const mergedPath = ref('')

const onionFontFamily = computed(() => getFontFamily(props.onionFont))

// 仅在切换字符（unicodeHex 真正变化）时才重置笔画
watch(
  () => (props.targetChar ? props.targetChar.codePointAt(0)?.toString(16).toUpperCase() : ''),
  (newHex, oldHex) => {
    if (newHex !== oldHex) {
      clear()
    }
  }
)

function syncActiveCanvasSize() {
  const canvas = activeCanvas.value
  const wrapper = canvasWrapper.value
  if (!canvas || !wrapper) return null

  const dpr = window.devicePixelRatio || 1
  const width = wrapper.clientWidth
  const height = wrapper.clientHeight
  if (width === 0 || height === 0) return null

  const targetW = Math.round(width * dpr)
  const targetH = Math.round(height * dpr)
  if (canvas.width !== targetW || canvas.height !== targetH) {
    canvas.width = targetW
    canvas.height = targetH
  }
  const ctx = canvas.getContext('2d')
  if (!ctx) return null
  return { ctx, targetW, targetH }
}

function clearActiveCanvas() {
  const canvas = activeCanvas.value
  if (!canvas) return
  const ctx = canvas.getContext('2d')
  if (!ctx) return
  ctx.setTransform(1, 0, 0, 1, 0, 0)
  ctx.clearRect(0, 0, canvas.width, canvas.height)
}

function renderActiveStrokeOnCanvas() {
  if (activePoints.length === 0) return
  const info = syncActiveCanvasSize()
  if (!info) return
  const { ctx, targetW, targetH } = info

  ctx.setTransform(1, 0, 0, 1, 0, 0)
  ctx.clearRect(0, 0, targetW, targetH)
  ctx.setTransform(targetW / 1000, 0, 0, targetH / 1000, 0, 0)

  const baseSize = props.brushOptions?.size || 48
  ctx.lineCap = 'round'
  ctx.lineJoin = 'round'
  ctx.strokeStyle = '#0f172a'
  ctx.fillStyle = '#0f172a'

  if (activePoints.length === 1) {
    const [x, y, p] = activePoints[0]
    const lWidth = baseSize * (0.25 + p * 0.9)
    ctx.beginPath()
    ctx.arc(x, y, lWidth / 2, 0, Math.PI * 2)
    ctx.fill()
    return
  }

  let prevMidX = activePoints[0][0]
  let prevMidY = activePoints[0][1]

  for (let i = 1; i < activePoints.length; i++) {
    const p1 = activePoints[i - 1]
    const p2 = activePoints[i]
    const midX = (p1[0] + p2[0]) / 2
    const midY = (p1[1] + p2[1]) / 2
    const pressure = (p1[2] + p2[2]) / 2

    ctx.lineWidth = baseSize * (0.25 + pressure * 0.9)
    ctx.beginPath()
    ctx.moveTo(prevMidX, prevMidY)
    ctx.quadraticCurveTo(p1[0], p1[1], midX, midY)
    ctx.stroke()

    prevMidX = midX
    prevMidY = midY
  }

  const last = activePoints[activePoints.length - 1]
  ctx.lineWidth = baseSize * (0.25 + last[2] * 0.9)
  ctx.beginPath()
  ctx.moveTo(prevMidX, prevMidY)
  ctx.lineTo(last[0], last[1])
  ctx.stroke()
}

function recomputeMergedPath() {
  if (strokes.value.length === 0) {
    mergedPath.value = ''
  } else {
    const paths = strokes.value.map((s) => s.path).filter(Boolean)
    try {
      const united = uniteSvgPaths(paths)
      mergedPath.value = united || paths.join(' ')
    } catch {
      mergedPath.value = paths.join(' ')
    }
  }
  emit('update:hasStrokes', strokes.value.length > 0)
}

// Re-render strokes if brush options change
watch(
  () => props.brushOptions,
  () => {
    if (strokes.value.length > 0) {
      strokes.value = strokes.value.map((s) => ({
        points: s.points,
        path: buildStrokePath(s.points, props.brushOptions),
      }))
      recomputeMergedPath()
    }
  },
  { deep: true }
)

function toLogicalCoords(clientX, clientY) {
  const rect = canvasWrapper.value.getBoundingClientRect()
  const x = ((clientX - rect.left) / rect.width) * 1000
  const y = ((clientY - rect.top) / rect.height) * 1000
  return [
    Math.max(0, Math.min(1000, x)),
    Math.max(0, Math.min(1000, y)),
  ]
}

function getPressure(e) {
  if (e.pointerType === 'pen' && typeof e.pressure === 'number' && e.pressure > 0) {
    return e.pressure
  }
  return 0.5
}

let mergeTimer = null

function scheduleRecomputeMergedPath() {
  if (mergeTimer) {
    clearTimeout(mergeTimer)
  }
  mergeTimer = setTimeout(() => {
    mergeTimer = null
    recomputeMergedPath()
  }, 0)
}

function finalizeCurrentStroke() {
  isDrawing.value = false
  activePointerId.value = null
  clearActiveCanvas()

  if (activePoints.length > 0) {
    const path = buildStrokePath(activePoints, props.brushOptions)
    if (path) {
      strokes.value.push({
        points: activePoints,
        path,
      })
      // 先立即拼接显示，避免异步合并期间闪烁，再异步执行 paper.js 布尔合并
      mergedPath.value = strokes.value.map((s) => s.path).filter(Boolean).join(' ')
      emit('update:hasStrokes', strokes.value.length > 0)
      scheduleRecomputeMergedPath()
      emit('stroke-end')
    }
  }
  activePoints = []
}

function handlePointerDown(e) {
  if (props.pencilOnly && e.pointerType !== 'pen') return
  if (e.button !== 0 && e.pointerType === 'mouse') return

  e.preventDefault()

  // 如果上一笔尚未正常结束，先安全收尾上一笔，然后立即以新点开始新一笔，绝不 return 丢弃
  if (isDrawing.value) {
    finalizeCurrentStroke()
  }

  try {
    e.currentTarget?.setPointerCapture?.(e.pointerId)
  } catch {}

  isDrawing.value = true
  activePointerId.value = e.pointerId
  const [x, y] = toLogicalCoords(e.clientX, e.clientY)
  activePoints = [[x, y, getPressure(e)]]
  renderActiveStrokeOnCanvas()
}

function handlePointerMove(e) {
  if (!isDrawing.value) return
  if (props.pencilOnly && e.pointerType !== 'pen') return

  e.preventDefault()
  const coalesced = typeof e.getCoalescedEvents === 'function' ? e.getCoalescedEvents() : null
  const events = coalesced && coalesced.length > 0 ? coalesced : [e]

  for (const ev of events) {
    const [x, y] = toLogicalCoords(ev.clientX, ev.clientY)
    activePoints.push([x, y, getPressure(ev)])
  }
  renderActiveStrokeOnCanvas()
}

function handlePointerUp(e) {
  if (!isDrawing.value) return
  e.preventDefault()
  finalizeCurrentStroke()
}

function undo() {
  if (strokes.value.length === 0) return
  strokes.value.pop()
  recomputeMergedPath()
}

function clear() {
  strokes.value = []
  activePoints = []
  mergedPath.value = ''
  clearActiveCanvas()
  emit('update:hasStrokes', false)
}

function getMergedSvgPath() {
  if (strokes.value.length === 0) return ''
  if (!mergedPath.value) {
    recomputeMergedPath()
  }
  return mergedPath.value
}

function getStrokesCount() {
  return strokes.value.length
}

defineExpose({
  undo,
  clear,
  getMergedSvgPath,
  getStrokesCount,
})
</script>

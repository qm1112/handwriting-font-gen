<template>
  <div class="h-full flex flex-col bg-slate-950 text-slate-100 select-none overflow-hidden">
    <!-- Top Progress & Toolbar -->
    <header class="shrink-0 border-b border-slate-800/80 bg-slate-900/80 backdrop-blur-md px-4 py-2.5">
      <div class="max-w-[1600px] mx-auto flex flex-wrap items-center justify-between gap-3">
        <!-- Brand & Progress -->
        <div class="flex items-center gap-4">
          <div class="flex items-center gap-2">
            <PenTool class="w-5 h-5 text-indigo-400" />
            <span class="font-semibold tracking-tight text-slate-100">手写字体工坊</span>
          </div>

          <div class="hidden sm:flex items-center gap-2.5 bg-slate-950/70 px-3 py-1.5 rounded-xl border border-slate-800">
            <span class="text-xs text-slate-400">进度</span>
            <div class="w-28 h-2 bg-slate-800 rounded-full overflow-hidden">
              <div
                class="h-full bg-indigo-500 transition-all duration-300"
                :style="{ width: `${progressPercent}%` }"
              />
            </div>
            <span class="text-xs font-mono text-slate-200">
              {{ completedCount }} / {{ activeGroupChars.length }}
            </span>
          </div>
        </div>

        <!-- Group Tabs -->
        <div class="flex items-center gap-1 bg-slate-950/70 p-1 rounded-xl border border-slate-800 overflow-x-auto">
          <button
            v-for="g in CHAR_GROUPS"
            :key="g.id"
            type="button"
            @click="selectGroup(g.id)"
            :class="[
              'px-3 py-1.5 rounded-lg text-xs font-medium whitespace-nowrap transition-colors',
              currentGroup === g.id
                ? 'bg-indigo-500 text-white shadow'
                : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800/60',
            ]"
          >
            {{ g.label }}
          </button>
        </div>

        <!-- Actions: Preview & Export -->
        <div class="flex items-center gap-2">
          <button
            type="button"
            @click="showPreviewModal = true"
            class="px-3 py-1.5 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-200 text-xs font-medium flex items-center gap-1.5 transition-colors"
          >
            <Eye class="w-4 h-4 text-indigo-400" />
            <span>排版预览</span>
          </button>

          <button
            type="button"
            @click="showExportModal = true"
            class="px-3.5 py-1.5 rounded-xl bg-emerald-500 hover:bg-emerald-400 text-slate-950 text-xs font-semibold flex items-center gap-1.5 transition-colors"
          >
            <Download class="w-4 h-4" />
            <span>导出 TTF</span>
          </button>

          <button
            type="button"
            @click="showRightPanel = !showRightPanel"
            :class="[
              'px-3 py-1.5 rounded-xl text-xs font-medium flex items-center gap-1.5 transition-colors',
              showRightPanel
                ? 'bg-indigo-500/20 text-indigo-300 border border-indigo-500/40'
                : 'bg-slate-800 hover:bg-slate-700 text-slate-300',
            ]"
            title="折叠/展开右侧设置栏"
          >
            <SlidersHorizontal class="w-4 h-4" />
            <span class="hidden sm:inline">{{ showRightPanel ? '收起设置' : '笔刷设置' }}</span>
          </button>
        </div>
      </div>

      <!-- Character Strip & Filter -->
      <div class="max-w-[1600px] mx-auto mt-2.5 flex items-center gap-2">
        <div class="flex items-center gap-1 shrink-0 bg-slate-950/70 p-0.5 rounded-lg border border-slate-800">
          <button
            v-for="f in [
              { id: 'all', label: '全部' },
              { id: 'unwritten', label: '未写' },
              { id: 'written', label: '已写' },
            ]"
            :key="f.id"
            type="button"
            @click="filterMode = f.id"
            :class="[
              'px-2.5 py-1 rounded-md text-xs font-medium transition-colors',
              filterMode === f.id ? 'bg-slate-700 text-white' : 'text-slate-400 hover:text-slate-200',
            ]"
          >
            {{ f.label }}
          </button>
        </div>

        <div class="flex-1 flex items-center gap-0 overflow-x-auto overscroll-contain bg-white/95 rounded-xl px-2.5 py-1 border border-slate-300/60">
          <button
            v-for="ch in visibleStripChars"
            :key="ch"
            type="button"
            @click="selectChar(ch)"
            :class="[
              'relative w-7 h-8 px-0 shrink-0 text-xl leading-none flex items-center justify-center transition-colors rounded-sm',
              currentChar === ch
                ? 'bg-blue-500/15'
                : 'hover:bg-slate-200/60',
              isCharWritten(ch) ? 'text-slate-900' : 'text-slate-400',
            ]"
          >
            <svg
              v-if="localSvgCache[charToUnicodeHex(ch)]"
              viewBox="0 0 1000 1000"
              class="w-5 h-5"
            >
              <path
                :d="localSvgCache[charToUnicodeHex(ch)]"
                fill="currentColor"
                fill-rule="nonzero"
              />
            </svg>
            <span v-else :style="{ fontFamily: onionFontFamily }">{{ ch }}</span>
            <span
              v-if="currentChar === ch"
              class="absolute bottom-0 left-1 right-1 h-0.5 bg-blue-500 rounded-full"
            />
          </button>
        </div>
      </div>
    </header>

    <!-- Main Workspace -->
    <main class="flex-1 max-w-[1600px] w-full mx-auto p-3 sm:p-5 flex flex-col lg:flex-row gap-5 overflow-hidden">
      <!-- Left / Bottom Fast Action Bar -->
      <aside class="order-2 lg:order-1 lg:w-44 shrink-0 flex lg:flex-col justify-between gap-3">
        <!-- Current Target Card -->
        <div class="hidden lg:flex flex-col items-center justify-center p-4 rounded-2xl bg-slate-900 border border-slate-800">
          <span class="text-xs text-slate-400 mb-1">当前书写</span>
          <span class="text-5xl font-bold text-white leading-none my-1">{{ currentChar }}</span>
          <span class="text-xs font-mono text-slate-500 mt-1">U+{{ currentUnicodeHex }}</span>
        </div>

        <!-- Big Touch-Friendly Action Buttons -->
        <div class="flex lg:flex-col gap-2.5 w-full">
          <button
            type="button"
            :disabled="!hasStrokes || saving"
            @click="handleUndo"
            class="flex-1 lg:flex-none py-3.5 px-4 rounded-2xl bg-slate-800 hover:bg-slate-700 disabled:opacity-40 text-slate-200 font-medium text-sm flex items-center justify-center gap-2 transition-colors active:scale-95"
          >
            <Undo2 class="w-5 h-5" />
            <span>撤销</span>
          </button>

          <button
            type="button"
            :disabled="!hasStrokes || saving"
            @click="handleClear"
            class="flex-1 lg:flex-none py-3.5 px-4 rounded-2xl bg-slate-800 hover:bg-rose-500/20 hover:text-rose-300 disabled:opacity-40 text-slate-200 font-medium text-sm flex items-center justify-center gap-2 transition-colors active:scale-95"
          >
            <Trash2 class="w-5 h-5" />
            <span>清空</span>
          </button>

          <button
            type="button"
            :disabled="!hasStrokes || saving"
            @click="handleSaveAndNext"
            class="flex-[1.5] lg:flex-none py-4 px-4 rounded-2xl bg-indigo-500 hover:bg-indigo-400 disabled:opacity-40 text-white font-semibold text-sm flex items-center justify-center gap-2 shadow-lg shadow-indigo-500/25 transition-all active:scale-95"
          >
            <Loader2 v-if="saving" class="w-5 h-5 animate-spin" />
            <Check v-else class="w-5 h-5" />
            <span>保存并下一个</span>
          </button>
        </div>

        <p class="hidden lg:block text-[11px] text-slate-500 text-center leading-relaxed">
          快捷键：<kbd class="px-1.5 py-0.5 bg-slate-800 rounded text-slate-300">Space</kbd> 或
          <kbd class="px-1.5 py-0.5 bg-slate-800 rounded text-slate-300">Enter</kbd> 保存并下一个
        </p>
      </aside>

      <!-- Center Writing Canvas -->
      <section class="order-1 lg:order-2 flex-1 flex flex-col items-center justify-center gap-3 min-h-[360px]">
        <div class="flex items-center gap-3 bg-slate-900/80 border border-slate-800 px-3.5 py-1.5 rounded-xl text-xs text-slate-300">
          <span class="whitespace-nowrap text-slate-400">画布大小</span>
          <input
            type="range"
            min="25"
            max="100"
            step="5"
            v-model.number="canvasScale"
            class="w-28 sm:w-36 accent-indigo-500"
          />
          <span class="font-mono text-slate-200 w-9 text-right">{{ canvasScale }}%</span>
        </div>

        <WritingCanvas
          ref="canvasRef"
          :target-char="currentChar"
          :brush-options="brushOptions"
          :pencil-only="pencilOnly"
          :guide-type="guideType"
          :show-onion-skin="showOnionSkin"
          :onion-font="onionFont"
          :onion-size="760"
          :onion-opacity="onionOpacity"
          :scale="canvasScale"
          @update:has-strokes="hasStrokes = $event"
          @stroke-end="handleStrokeEnd"
        />
      </section>

      <!-- Right Brush & Guide Settings Panel -->
      <aside
        v-if="showRightPanel"
        class="order-3 lg:w-72 shrink-0 bg-slate-900 border border-slate-800 rounded-2xl p-4 overflow-y-auto overscroll-contain"
      >
        <div class="flex items-center justify-between mb-3 pb-2 border-b border-slate-800">
          <span class="text-xs font-semibold text-slate-300">笔刷与字帖设置</span>
          <button
            type="button"
            @click="showRightPanel = false"
            class="text-xs text-slate-400 hover:text-slate-200 px-2 py-0.5 rounded bg-slate-800 hover:bg-slate-700 transition-colors"
          >
            折叠
          </button>
        </div>
        <BrushPanel
          :brush="brushOptions"
          v-model:pencil-only="pencilOnly"
          v-model:guide-type="guideType"
          v-model:show-onion-skin="showOnionSkin"
          v-model:onion-font="onionFont"
          v-model:onion-opacity="onionOpacity"
          @update:brush="brushOptions = $event"
          @reset-brush="resetBrush"
        />
      </aside>
    </main>

    <!-- Toast Notification -->
    <div
      v-if="toastMsg"
      class="fixed bottom-5 left-1/2 -translate-x-1/2 z-50 px-4 py-2 rounded-xl bg-slate-800 border border-slate-700 text-slate-100 text-xs font-medium shadow-xl"
    >
      {{ toastMsg }}
    </div>

    <!-- Modals -->
    <PreviewModal
      :open="showPreviewModal"
      :local-svg-cache="localSvgCache"
      @close="showPreviewModal = false"
    />
    <ExportModal
      :open="showExportModal"
      @close="showExportModal = false"
    />
  </div>
</template>

<script setup>
import { ref, computed, watch, onMounted, onUnmounted } from 'vue'
import {
  PenTool,
  Eye,
  Download,
  Undo2,
  Trash2,
  Check,
  Loader2,
  SlidersHorizontal,
} from 'lucide-vue-next'
import WritingCanvas from './components/WritingCanvas.vue'
import BrushPanel from './components/BrushPanel.vue'
import PreviewModal from './components/PreviewModal.vue'
import ExportModal from './components/ExportModal.vue'
import {
  CHAR_GROUPS,
  FALLBACK_GROUP_CHARS,
  charToUnicodeHex,
} from './data/charsets'
import { getFontFamily } from './utils/fontMap'

const SETTINGS_STORAGE_KEY = 'fontgen_settings_v1'
const LEGACY_BRUSH_STORAGE_KEY = 'hw_font_gen_brush_v2'
const DEFAULT_BRUSH = {
  size: 48,
  thinning: 0.55,
  smoothing: 0.5,
  streamline: 0.45,
  startTaper: 15,
  endTaper: 25,
}

const DEFAULT_SETTINGS = {
  brush: { ...DEFAULT_BRUSH },
  refFont: 'ma_shan_zheng',
  refOpacity: 0.18,
  pencilOnly: false,
  canvasScale: 100,
  showRightPanel: true,
}

function loadSavedSettings() {
  try {
    const raw = localStorage.getItem(SETTINGS_STORAGE_KEY)
    if (raw) {
      const parsed = JSON.parse(raw)
      return {
        ...DEFAULT_SETTINGS,
        ...parsed,
        brush: { ...DEFAULT_BRUSH, ...(parsed.brush || {}) },
      }
    }
    const legacyBrushRaw = localStorage.getItem(LEGACY_BRUSH_STORAGE_KEY)
    if (legacyBrushRaw) {
      return {
        ...DEFAULT_SETTINGS,
        brush: { ...DEFAULT_BRUSH, ...JSON.parse(legacyBrushRaw) },
      }
    }
  } catch {}
  return { ...DEFAULT_SETTINGS, brush: { ...DEFAULT_BRUSH } }
}

const savedSettings = loadSavedSettings()
const brushOptions = ref(savedSettings.brush)

function resetBrush() {
  brushOptions.value = { ...DEFAULT_BRUSH }
}

// Canvas & Guide settings
const canvasScale = ref(savedSettings.canvasScale)
const pencilOnly = ref(savedSettings.pencilOnly)
const guideType = ref('mi')
const showOnionSkin = ref(true)
const onionFont = ref(savedSettings.refFont)
const onionFontFamily = computed(() => getFontFamily(onionFont.value))
const onionOpacity = ref(savedSettings.refOpacity)
const showRightPanel = ref(savedSettings.showRightPanel)

watch(
  [brushOptions, onionFont, onionOpacity, pencilOnly, canvasScale, showRightPanel],
  () => {
    try {
      localStorage.setItem(
        SETTINGS_STORAGE_KEY,
        JSON.stringify({
          brush: brushOptions.value,
          refFont: onionFont.value,
          refOpacity: onionOpacity.value,
          pencilOnly: pencilOnly.value,
          canvasScale: canvasScale.value,
          showRightPanel: showRightPanel.value,
        })
      )
    } catch {}
  },
  { deep: true }
)

// Charset & Progress state
const currentGroup = ref('basic50')
const filterMode = ref('all') // 'all' | 'unwritten' | 'written'
const groupCharsMap = ref({ ...FALLBACK_GROUP_CHARS })
const writtenHexSet = ref(new Set())
const localSvgCache = ref({})
const currentChar = ref(FALLBACK_GROUP_CHARS.basic50[0])

const canvasRef = ref(null)
const hasStrokes = ref(false)
const saving = ref(false)
const toastMsg = ref('')
const showPreviewModal = ref(false)
const showExportModal = ref(false)

const currentUnicodeHex = computed(() => charToUnicodeHex(currentChar.value))
const activeGroupChars = computed(() => groupCharsMap.value[currentGroup.value] || [])

const completedCount = computed(() =>
  activeGroupChars.value.filter((ch) => writtenHexSet.value.has(charToUnicodeHex(ch))).length
)

const progressPercent = computed(() => {
  const total = activeGroupChars.value.length
  if (total === 0) return 0
  return Math.round((completedCount.value / total) * 100)
})

const filteredChars = computed(() => {
  return activeGroupChars.value.filter((ch) => {
    const written = writtenHexSet.value.has(charToUnicodeHex(ch))
    if (filterMode.value === 'written') return written
    if (filterMode.value === 'unwritten') return !written
    return true
  })
})

const visibleStripChars = computed(() => {
  const list = filteredChars.value
  if (list.length <= 500) return list
  const idx = list.indexOf(currentChar.value)
  const center = idx >= 0 ? idx : 0
  const start = Math.max(0, center - 40)
  const end = Math.min(list.length, center + 41)
  return list.slice(start, end)
})

function isCharWritten(ch) {
  return writtenHexSet.value.has(charToUnicodeHex(ch))
}

function showToast(msg) {
  toastMsg.value = msg
  setTimeout(() => {
    if (toastMsg.value === msg) toastMsg.value = ''
  }, 2200)
}

let strokeSyncTimer = null

function handleStrokeEnd() {
  if (strokeSyncTimer) clearTimeout(strokeSyncTimer)
  strokeSyncTimer = setTimeout(() => {
    strokeSyncTimer = null
    saveCurrentCharSilently()
  }, 400)
}

async function saveCurrentCharSilently() {
  if (!hasStrokes.value || saving.value) return
  const mergedSvgPath = canvasRef.value?.getMergedSvgPath()
  if (!mergedSvgPath) return

  const hex = currentUnicodeHex.value
  const ch = currentChar.value

  writtenHexSet.value.add(hex)
  localSvgCache.value[hex] = mergedSvgPath

  try {
    await fetch(`api/char/${hex}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        char: ch,
        unicode_hex: hex,
        merged_svg_path: mergedSvgPath,
      }),
    })
  } catch {
    // Silent fallback; already cached locally
  }
}

async function selectGroup(groupId) {
  if (groupId !== currentGroup.value) {
    await saveCurrentCharSilently()
  }
  currentGroup.value = groupId
  const list = groupCharsMap.value[groupId] || []
  const firstUnwritten = list.find((ch) => !isCharWritten(ch))
  currentChar.value = firstUnwritten || list[0] || ''
  canvasRef.value?.clear()
}

async function selectChar(ch) {
  if (ch === currentChar.value) return
  await saveCurrentCharSilently()
  currentChar.value = ch
  canvasRef.value?.clear()
}

function handleUndo() {
  canvasRef.value?.undo()
}

function handleClear() {
  canvasRef.value?.clear()
}

function moveToNextUnwritten() {
  const list = activeGroupChars.value
  const currentIdx = list.indexOf(currentChar.value)
  for (let i = currentIdx + 1; i < list.length; i++) {
    if (!isCharWritten(list[i])) {
      currentChar.value = list[i]
      return
    }
  }
  for (let i = 0; i < currentIdx; i++) {
    if (!isCharWritten(list[i])) {
      currentChar.value = list[i]
      return
    }
  }
  // If all written, advance to next char
  if (currentIdx >= 0 && currentIdx + 1 < list.length) {
    currentChar.value = list[currentIdx + 1]
  }
}

async function handleSaveAndNext() {
  if (!hasStrokes.value || saving.value) return
  const mergedSvgPath = canvasRef.value?.getMergedSvgPath()
  if (!mergedSvgPath) return

  const hex = currentUnicodeHex.value
  const ch = currentChar.value
  saving.value = true

  try {
    const res = await fetch(`api/char/${hex}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        char: ch,
        unicode_hex: hex,
        merged_svg_path: mergedSvgPath,
      }),
    })

    if (!res.ok) {
      throw new Error(`HTTP ${res.status}`)
    }

    writtenHexSet.value.add(hex)
    localSvgCache.value[hex] = mergedSvgPath
    canvasRef.value?.clear()
    moveToNextUnwritten()
  } catch (err) {
    // Still cache locally so user doesn't lose work if backend is offline
    writtenHexSet.value.add(hex)
    localSvgCache.value[hex] = mergedSvgPath
    canvasRef.value?.clear()
    moveToNextUnwritten()
    showToast(`已暂存本地（后端未连接: ${err.message}）`)
  } finally {
    saving.value = false
  }
}

async function loadCharsetsFromBackend() {
  try {
    const res = await fetch('api/charsets')
    if (!res.ok) return
    const data = await res.json()
    groupCharsMap.value = {
      basic50: Array.isArray(data.basic_50) ? data.basic_50 : groupCharsMap.value.basic50,
      level1: Array.isArray(data.level1_3500) ? data.level1_3500 : groupCharsMap.value.level1,
      gb2312: Array.isArray(data.gb2312_ext) ? data.gb2312_ext : groupCharsMap.value.gb2312,
      ascii: Array.isArray(data.punct_ascii) ? data.punct_ascii : groupCharsMap.value.ascii,
    }
    const activeList = groupCharsMap.value[currentGroup.value] || []
    if (activeList.length > 0 && !activeList.includes(currentChar.value)) {
      currentChar.value = activeList[0]
    }
  } catch {
    // Backend may not be running yet; silent fallback
  }
}

async function loadProgressFromBackend() {
  try {
    const res = await fetch('api/progress')
    if (res.ok) {
      const data = await res.json()
      if (Array.isArray(data.written)) {
        writtenHexSet.value = new Set(data.written.map((h) => String(h).toUpperCase()))
      }
    }
  } catch {
    // Backend may not be running yet; silent fallback
  }
}

function handleKeyDown(e) {
  if (showPreviewModal.value || showExportModal.value) return
  if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return

  if (e.code === 'Space' || e.code === 'Enter') {
    e.preventDefault()
    if (hasStrokes.value && !saving.value) {
      handleSaveAndNext()
    }
  } else if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'z') {
    e.preventDefault()
    handleUndo()
  }
}

function preventGesture(e) {
  e.preventDefault()
}

function preventMultiTouchMove(e) {
  if (e.touches.length > 1) {
    e.preventDefault()
  }
}

onMounted(() => {
  loadCharsetsFromBackend()
  loadProgressFromBackend()
  window.addEventListener('keydown', handleKeyDown)
  document.addEventListener('gesturestart', preventGesture, { passive: false })
  document.addEventListener('touchmove', preventMultiTouchMove, { passive: false })
})

onUnmounted(() => {
  if (strokeSyncTimer) clearTimeout(strokeSyncTimer)
  window.removeEventListener('keydown', handleKeyDown)
  document.removeEventListener('gesturestart', preventGesture)
  document.removeEventListener('touchmove', preventMultiTouchMove)
})
</script>

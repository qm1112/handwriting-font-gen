<template>
  <div
    v-if="open"
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-sm p-4"
    @click.self="$emit('close')"
  >
    <div class="w-full max-w-3xl bg-slate-900 border border-slate-700/80 rounded-2xl shadow-2xl overflow-hidden flex flex-col max-h-[88vh]">
      <div class="flex items-center justify-between px-5 py-4 border-b border-slate-800">
        <div class="flex items-center gap-2">
          <Eye class="w-5 h-5 text-indigo-400" />
          <h2 class="text-base font-semibold text-slate-100">句子排版预览</h2>
        </div>
        <button
          type="button"
          class="p-1.5 rounded-lg text-slate-400 hover:text-slate-100 hover:bg-slate-800 transition-colors"
          @click="$emit('close')"
        >
          <X class="w-5 h-5" />
        </button>
      </div>

      <div class="p-5 space-y-4 overflow-y-auto">
        <div class="flex flex-col sm:flex-row gap-3">
          <input
            v-model="previewText"
            type="text"
            placeholder="输入任意句子测试手写字体大小与重心..."
            class="flex-1 px-3.5 py-2.5 rounded-xl bg-slate-950 border border-slate-700 text-slate-100 placeholder-slate-500 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
          />
          <div class="flex items-center gap-2 shrink-0">
            <span class="text-xs text-slate-400">字号</span>
            <input
              v-model.number="fontSize"
              type="range"
              min="28"
              max="96"
              step="2"
              class="w-24 accent-indigo-500"
            />
            <span class="text-xs font-mono text-slate-300 w-9">{{ fontSize }}px</span>
          </div>
        </div>

        <!-- Preview Paper -->
        <div class="min-h-[240px] p-6 rounded-xl bg-white text-slate-900 shadow-inner flex flex-wrap items-center content-start gap-y-2">
          <template v-for="(item, idx) in renderedChars" :key="idx">
            <br v-if="item.char === '\n'" class="w-full" />
            <span
              v-else-if="item.char === ' '"
              :style="{ width: `${fontSize * 0.4}px`, height: `${fontSize}px` }"
              class="inline-block"
            />
            <svg
              v-else-if="item.svgPath"
              viewBox="0 0 1000 1000"
              :style="{ width: `${fontSize}px`, height: `${fontSize}px` }"
              class="inline-block shrink-0"
            >
              <path :d="item.svgPath" fill="#0f172a" fill-rule="nonzero" />
            </svg>
            <span
              v-else
              :style="{
                width: `${fontSize}px`,
                height: `${fontSize}px`,
                fontSize: `${fontSize * 0.72}px`,
                lineHeight: `${fontSize}px`,
              }"
              class="inline-flex items-center justify-center text-slate-300 border border-dashed border-slate-200 rounded"
              title="尚未书写该字"
            >
              {{ item.char }}
            </span>
          </template>
        </div>

        <p class="text-xs text-slate-400">
          提示：已书写的汉字会以矢量路径渲染，未书写的汉字将显示为浅灰色虚线占位符。
        </p>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, watch } from 'vue'
import { Eye, X } from 'lucide-vue-next'
import { charToUnicodeHex } from '../data/charsets'

const props = defineProps({
  open: { type: Boolean, default: false },
  localSvgCache: { type: Object, default: () => ({}) },
})

defineEmits(['close'])

const previewText = ref('的一是在不了有和人这中大为上个国')
const fontSize = ref(56)
const fetchedSvgMap = ref({})
const renderedChars = ref([])

async function refreshPreview() {
  const chars = Array.from(previewText.value || '')
  const missingHexes = new Set()

  for (const ch of chars) {
    if (ch === '\n' || ch === ' ') continue
    const hex = charToUnicodeHex(ch)
    if (!props.localSvgCache[hex] && !(hex in fetchedSvgMap.value)) {
      missingHexes.add(hex)
    }
  }

  // Fetch missing characters from backend
  await Promise.all(
    Array.from(missingHexes).map(async (hex) => {
      try {
        const res = await fetch(`api/char/${hex}`)
        if (res.ok) {
          const data = await res.json()
          fetchedSvgMap.value[hex] = data.merged_svg_path || data.svg_path || ''
        } else {
          fetchedSvgMap.value[hex] = ''
        }
      } catch {
        fetchedSvgMap.value[hex] = ''
      }
    })
  )

  renderedChars.value = chars.map((ch) => {
    const hex = charToUnicodeHex(ch)
    const svgPath = props.localSvgCache[hex] || fetchedSvgMap.value[hex] || ''
    return { char: ch, hex, svgPath }
  })
}

watch(
  () => [props.open, previewText.value],
  ([isOpen]) => {
    if (isOpen) {
      refreshPreview()
    }
  },
  { immediate: true }
)
</script>

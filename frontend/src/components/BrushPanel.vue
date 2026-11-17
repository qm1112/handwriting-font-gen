<template>
  <div class="space-y-5 text-sm">
    <!-- Brush Parameters -->
    <div class="space-y-3">
      <div class="flex items-center justify-between">
        <h3 class="text-xs font-semibold uppercase tracking-wider text-slate-400">笔刷预设</h3>
        <button
          type="button"
          class="text-xs text-indigo-400 hover:text-indigo-300 transition-colors"
          @click="$emit('reset-brush')"
        >
          恢复默认
        </button>
      </div>

      <div class="grid grid-cols-3 gap-1.5">
        <button
          v-for="preset in BRUSH_PRESETS"
          :key="preset.id"
          type="button"
          @click="applyPreset(preset)"
          :class="[
            'py-2 rounded-lg text-xs font-medium transition-colors border',
            activePresetId === preset.id
              ? 'bg-indigo-500 text-white border-indigo-400 shadow'
              : 'bg-slate-800 text-slate-300 border-slate-700/60 hover:bg-slate-700',
          ]"
        >
          {{ preset.label }}
        </button>
      </div>

      <button
        type="button"
        @click="showAdvanced = !showAdvanced"
        class="w-full flex items-center justify-between py-1.5 px-2.5 rounded-lg bg-slate-800/60 hover:bg-slate-800 text-xs text-slate-300 transition-colors"
      >
        <span>高级参数</span>
        <span class="text-slate-400">{{ showAdvanced ? '▲' : '▼' }}</span>
      </button>

      <div v-if="showAdvanced" class="space-y-2.5 pt-1">
        <div>
          <div class="flex justify-between text-xs mb-1">
            <span class="text-slate-300">粗细 (Size)</span>
            <span class="text-slate-400 font-mono">{{ brush.size }}</span>
          </div>
          <input
            type="range"
            min="20"
            max="100"
            step="1"
            :value="brush.size"
            @input="updateBrush('size', Number($event.target.value))"
            class="w-full accent-indigo-500"
          />
        </div>

        <div>
          <div class="flex justify-between text-xs mb-1">
            <span class="text-slate-300">笔锋变化 (Thinning)</span>
            <span class="text-slate-400 font-mono">{{ brush.thinning.toFixed(2) }}</span>
          </div>
          <input
            type="range"
            min="0"
            max="1"
            step="0.05"
            :value="brush.thinning"
            @input="updateBrush('thinning', Number($event.target.value))"
            class="w-full accent-indigo-500"
          />
        </div>

        <div>
          <div class="flex justify-between text-xs mb-1">
            <span class="text-slate-300">平滑度 (Smoothing)</span>
            <span class="text-slate-400 font-mono">{{ brush.smoothing.toFixed(2) }}</span>
          </div>
          <input
            type="range"
            min="0"
            max="1"
            step="0.05"
            :value="brush.smoothing"
            @input="updateBrush('smoothing', Number($event.target.value))"
            class="w-full accent-indigo-500"
          />
        </div>

        <div>
          <div class="flex justify-between text-xs mb-1">
            <span class="text-slate-300">流线稳定 (Streamline)</span>
            <span class="text-slate-400 font-mono">{{ brush.streamline.toFixed(2) }}</span>
          </div>
          <input
            type="range"
            min="0"
            max="1"
            step="0.05"
            :value="brush.streamline"
            @input="updateBrush('streamline', Number($event.target.value))"
            class="w-full accent-indigo-500"
          />
        </div>

        <div class="grid grid-cols-2 gap-2.5">
          <div>
            <div class="flex justify-between text-xs mb-1">
              <span class="text-slate-300">起笔尖 (Start)</span>
              <span class="text-slate-400 font-mono">{{ brush.startTaper }}</span>
            </div>
            <input
              type="range"
              min="0"
              max="100"
              step="2"
              :value="brush.startTaper"
              @input="updateBrush('startTaper', Number($event.target.value))"
              class="w-full accent-indigo-500"
            />
          </div>
          <div>
            <div class="flex justify-between text-xs mb-1">
              <span class="text-slate-300">收笔尖 (End)</span>
              <span class="text-slate-400 font-mono">{{ brush.endTaper }}</span>
            </div>
            <input
              type="range"
              min="0"
              max="100"
              step="2"
              :value="brush.endTaper"
              @input="updateBrush('endTaper', Number($event.target.value))"
              class="w-full accent-indigo-500"
            />
          </div>
        </div>
      </div>
    </div>

    <hr class="border-slate-800" />

    <!-- Onion Skin & Guide Settings -->
    <div class="space-y-3">
      <h3 class="text-xs font-semibold uppercase tracking-wider text-slate-400">辅助线与字帖</h3>

      <div class="flex items-center justify-between">
        <span class="text-xs text-slate-300">仅允许 Apple Pencil</span>
        <button
          type="button"
          role="switch"
          :aria-checked="pencilOnly"
          @click="$emit('update:pencilOnly', !pencilOnly)"
          :class="[
            'relative inline-flex h-5 w-9 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors',
            pencilOnly ? 'bg-indigo-500' : 'bg-slate-700',
          ]"
        >
          <span
            :class="[
              'pointer-events-none inline-block h-4 w-4 transform rounded-full bg-white shadow transition',
              pencilOnly ? 'translate-x-4' : 'translate-x-0',
            ]"
          />
        </button>
      </div>

      <div>
        <span class="block text-xs text-slate-300 mb-1.5">辅助格</span>
        <div class="grid grid-cols-3 gap-1.5">
          <button
            v-for="g in [
              { id: 'mi', label: '米字格' },
              { id: 'jiu', label: '九宫格' },
              { id: 'none', label: '无' },
            ]"
            :key="g.id"
            type="button"
            @click="$emit('update:guideType', g.id)"
            :class="[
              'py-1.5 rounded-lg text-xs font-medium transition-colors',
              guideType === g.id
                ? 'bg-indigo-500 text-white'
                : 'bg-slate-800 text-slate-300 hover:bg-slate-700',
            ]"
          >
            {{ g.label }}
          </button>
        </div>
      </div>

      <div class="flex items-center justify-between">
        <span class="text-xs text-slate-300">显示字帖底图</span>
        <button
          type="button"
          role="switch"
          :aria-checked="showOnionSkin"
          @click="$emit('update:showOnionSkin', !showOnionSkin)"
          :class="[
            'relative inline-flex h-5 w-9 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors',
            showOnionSkin ? 'bg-indigo-500' : 'bg-slate-700',
          ]"
        >
          <span
            :class="[
              'pointer-events-none inline-block h-4 w-4 transform rounded-full bg-white shadow transition',
              showOnionSkin ? 'translate-x-4' : 'translate-x-0',
            ]"
          />
        </button>
      </div>

      <template v-if="showOnionSkin">
        <div>
          <span class="block text-xs text-slate-300 mb-1.5">参考字体</span>
          <select
            :value="onionFont"
            @change="$emit('update:onionFont', $event.target.value)"
            class="w-full py-1.5 px-2.5 rounded-lg text-xs font-medium bg-slate-800 text-slate-200 border border-slate-700 focus:outline-none focus:border-indigo-500"
          >
            <option value="ma_shan_zheng">毛笔楷书 (Ma Shan Zheng)</option>
            <option value="noto_sans">黑体 (Noto Sans SC)</option>
            <option value="noto_serif">宋体 (Noto Serif SC)</option>
            <option value="zcool_xiaowei">小薇体 (ZCOOL XiaoWei)</option>
            <option value="long_cang">行草 (Long Cang)</option>
            <option value="kaiti">系统楷体 (Kaiti SC)</option>
          </select>
        </div>

        <div>
          <div class="flex justify-between text-xs mb-1">
            <span class="text-slate-300">底图透明度</span>
            <span class="text-slate-400 font-mono">{{ Math.round(onionOpacity * 100) }}%</span>
          </div>
          <input
            type="range"
            min="0"
            max="0.5"
            step="0.01"
            :value="onionOpacity"
            @input="$emit('update:onionOpacity', Number($event.target.value))"
            class="w-full accent-indigo-500"
          />
        </div>
      </template>
    </div>
  </div>
</template>

<script setup>
import { ref, computed } from 'vue'

const BRUSH_PRESETS = [
  {
    id: 'pen',
    label: '钢笔',
    options: { size: 48, thinning: 0.55, smoothing: 0.5, streamline: 0.45, startTaper: 15, endTaper: 25 },
  },
  {
    id: 'ballpoint',
    label: '圆珠笔',
    options: { size: 36, thinning: 0.15, smoothing: 0.6, streamline: 0.5, startTaper: 5, endTaper: 5 },
  },
  {
    id: 'brush',
    label: '毛笔',
    options: { size: 72, thinning: 0.85, smoothing: 0.65, streamline: 0.55, startTaper: 35, endTaper: 45 },
  },
]

const showAdvanced = ref(false)

const props = defineProps({
  brush: { type: Object, required: true },
  pencilOnly: { type: Boolean, default: false },
  guideType: { type: String, default: 'mi' },
  showOnionSkin: { type: Boolean, default: true },
  onionFont: { type: String, default: 'kaiti' },
  onionOpacity: { type: Number, default: 0.18 },
})

const emit = defineEmits([
  'update:brush',
  'reset-brush',
  'update:pencilOnly',
  'update:guideType',
  'update:showOnionSkin',
  'update:onionFont',
  'update:onionOpacity',
])

const activePresetId = computed(() => {
  const found = BRUSH_PRESETS.find((p) =>
    Object.entries(p.options).every(([k, v]) => props.brush[k] === v)
  )
  return found ? found.id : null
})

function applyPreset(preset) {
  emit('update:brush', { ...preset.options })
}

function updateBrush(key, value) {
  emit('update:brush', { ...props.brush, [key]: value })
}
</script>

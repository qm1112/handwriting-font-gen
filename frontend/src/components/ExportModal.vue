<template>
  <div
    v-if="open"
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-sm p-4"
    @click.self="$emit('close')"
  >
    <div class="w-full max-w-md bg-slate-900 border border-slate-700/80 rounded-2xl shadow-2xl overflow-hidden">
      <div class="flex items-center justify-between px-5 py-4 border-b border-slate-800">
        <div class="flex items-center gap-2">
          <Download class="w-5 h-5 text-emerald-400" />
          <h2 class="text-base font-semibold text-slate-100">导出 TTF 字体</h2>
        </div>
        <button
          type="button"
          class="p-1.5 rounded-lg text-slate-400 hover:text-slate-100 hover:bg-slate-800 transition-colors"
          @click="$emit('close')"
        >
          <X class="w-5 h-5" />
        </button>
      </div>

      <form class="p-5 space-y-4" @submit.prevent="handleExport">
        <div>
          <label class="block text-xs font-medium text-slate-300 mb-1.5">字体名称 (Font Family)</label>
          <input
            v-model="fontName"
            type="text"
            required
            placeholder="MyHandwriting"
            class="w-full px-3.5 py-2.5 rounded-xl bg-slate-950 border border-slate-700 text-slate-100 text-sm focus:outline-none focus:ring-2 focus:ring-emerald-500"
          />
        </div>

        <div>
          <label class="block text-xs font-medium text-slate-300 mb-1.5">字重 (Weight)</label>
          <select
            v-model="fontWeight"
            class="w-full px-3.5 py-2.5 rounded-xl bg-slate-950 border border-slate-700 text-slate-100 text-sm focus:outline-none focus:ring-2 focus:ring-emerald-500"
          >
            <option value="Regular">Regular (400)</option>
            <option value="Medium">Medium (500)</option>
            <option value="Bold">Bold (700)</option>
          </select>
        </div>

        <p v-if="errorMsg" class="text-xs text-rose-400 bg-rose-500/10 border border-rose-500/20 rounded-lg px-3 py-2">
          {{ errorMsg }}
        </p>

        <div class="flex items-center justify-end gap-2.5 pt-2">
          <button
            type="button"
            class="px-4 py-2 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-300 text-sm font-medium transition-colors"
            @click="$emit('close')"
          >
            取消
          </button>
          <button
            type="submit"
            :disabled="exporting"
            class="px-5 py-2 rounded-xl bg-emerald-500 hover:bg-emerald-400 disabled:opacity-50 text-slate-950 text-sm font-semibold transition-colors flex items-center gap-2"
          >
            <Loader2 v-if="exporting" class="w-4 h-4 animate-spin" />
            <span>{{ exporting ? '正在生成...' : '生成并下载 .ttf' }}</span>
          </button>
        </div>
      </form>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { Download, X, Loader2 } from 'lucide-vue-next'

defineProps({
  open: { type: Boolean, default: false },
})

const emit = defineEmits(['close'])

const fontName = ref('MyHandwriting')
const fontWeight = ref('Regular')
const exporting = ref(false)
const errorMsg = ref('')

async function handleExport() {
  errorMsg.value = ''
  exporting.value = true
  try {
    const res = await fetch('api/export/ttf', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        font_name: fontName.value.trim() || 'MyHandwriting',
        font_weight: fontWeight.value,
      }),
    })

    if (!res.ok) {
      const text = await res.text()
      throw new Error(text || `导出失败 (${res.status})`)
    }

    const blob = await res.blob()
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `${fontName.value.trim() || 'MyHandwriting'}-${fontWeight.value}.ttf`
    document.body.appendChild(a)
    a.click()
    a.remove()
    URL.revokeObjectURL(url)
    emit('close')
  } catch (err) {
    errorMsg.value = err.message || '导出失败，请检查后端服务是否运行'
  } finally {
    exporting.value = false
  }
}
</script>

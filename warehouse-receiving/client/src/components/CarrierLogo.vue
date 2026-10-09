<script setup>
// Logo don gian bang chu cai + mau thuong hieu (khong dung tai san thuong hieu that)
import { computed } from 'vue';
const props = defineProps({ name: { type: String, required: true }, size: { type: String, default: 'md' } });

const palette = {
  usps: ['bg-blue-800', 'text-red-300', 'USPS'],
  dhl: ['bg-yellow-400', 'text-red-600', 'DHL'],
  fedex: ['bg-purple-700', 'text-orange-400', 'FedEx'],
  ups: ['bg-amber-900', 'text-yellow-400', 'UPS'],
  amazon: ['bg-slate-800', 'text-orange-400', 'AMZ'],
};
const info = computed(() => {
  const key = Object.keys(palette).find((k) => props.name.toLowerCase().includes(k)) || null;
  return key ? palette[key] : ['bg-slate-200', 'text-slate-600', props.name.slice(0, 3).toUpperCase()];
});
const dim = computed(() => (props.size === 'lg' ? 'h-14 w-14 text-base' : 'h-8 w-8 text-[10px]'));
</script>

<template>
  <div class="flex shrink-0 items-center justify-center rounded-lg font-black tracking-tight" :class="[info[0], info[1], dim]">{{ info[2] }}</div>
</template>

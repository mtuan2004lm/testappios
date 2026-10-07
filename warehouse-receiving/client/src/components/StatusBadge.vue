<script setup>
defineProps({ status: String });
</script>

<template>
  <span class="inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-bold"
    :class="status === 'OPEN' ? 'bg-emerald-100 text-emerald-700' : 'bg-slate-200 text-slate-600'">
    <span class="h-1.5 w-1.5 rounded-full" :class="status === 'OPEN' ? 'animate-pulse bg-emerald-500' : 'bg-slate-400'"></span>{{ status }}
  </span>
</template>

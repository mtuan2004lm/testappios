<script setup>
import { tr } from '../i18n';
import { Construction } from 'lucide-vue-next';
defineProps({ title: String });
</script>

<template>
  <div class="card flex flex-col items-center gap-3 py-24 text-slate-500">
    <Construction class="h-10 w-10 text-accent" />
    <h1 class="text-xl font-bold text-navy">{{ tr(title) }}</h1>
    <p class="text-sm">{{ tr('Chức năng này sẽ được bổ sung ở giai đoạn sau.') }}</p>
  </div>
</template>

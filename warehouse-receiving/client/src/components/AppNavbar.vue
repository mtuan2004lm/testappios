<script setup>
import { ref } from 'vue';
import { Boxes, ChevronDown, Globe } from 'lucide-vue-next';

// Tab "Nhan hang" active ca khi dang o man hinh quet (route con cua /receiving)
const tabs = [
  { label: 'Nhận hàng', to: '/receiving/sessions', match: '/receiving' },
  { label: 'Danh sách mặt hàng', to: '/items', match: '/items' },
  { label: 'Chuyến bay', to: '/flights', match: '/flights' },
  { label: 'Báo cáo tracking', to: '/reports', match: '/reports' },
];
const warehouses = ['OR_1 - Hub Oregon', 'CA_1 - Hub California', 'TX_1 - Hub Texas'];
const warehouse = ref(warehouses[0]);
</script>

<template>
  <header class="bg-navy text-white shadow-md">
    <div class="mx-auto flex max-w-[1400px] flex-wrap items-center gap-x-8 gap-y-2 px-4 py-3 sm:px-6">
      <!-- Logo + doi kho -->
      <div class="flex items-center gap-3">
        <div class="flex h-9 w-9 items-center justify-center rounded-lg bg-accent"><Boxes class="h-5 w-5" /></div>
        <div class="leading-tight">
          <div class="text-base font-extrabold tracking-tight">Tina<span class="text-accent">Shipping</span></div>
          <div class="relative">
            <select v-model="warehouse" class="cursor-pointer appearance-none bg-transparent pr-5 text-xs text-slate-300 outline-none">
              <option v-for="w in warehouses" :key="w" :value="w" class="text-slate-800">{{ w }}</option>
            </select>
            <ChevronDown class="pointer-events-none absolute right-0 top-0.5 h-3.5 w-3.5 text-slate-400" />
          </div>
        </div>
      </div>

      <!-- Tabs -->
      <nav class="order-last flex w-full gap-1 overflow-x-auto lg:order-none lg:w-auto lg:flex-1">
        <RouterLink v-for="t in tabs" :key="t.to" :to="t.to"
          class="whitespace-nowrap rounded-md px-4 py-2 text-sm font-medium text-slate-300 transition hover:bg-white/10 hover:text-white"
          :class="{ '!bg-white/15 !text-white shadow-[inset_0_-2px_0_#f97316]': $route.path.startsWith(t.match) }">
          {{ t.label }}
        </RouterLink>
      </nav>

      <!-- User -->
      <div class="ml-auto flex items-center gap-5 text-sm">
        <span class="flex items-center gap-1.5 text-slate-300"><Globe class="h-4 w-4" /> Tiếng Việt</span>
        <div class="flex items-center gap-2.5">
          <div class="flex h-8 w-8 items-center justify-center rounded-full bg-accent text-xs font-bold">N1</div>
          <div class="leading-tight">
            <div class="font-semibold">Nhan vien 01</div>
            <div class="flex items-center gap-1.5 text-xs text-emerald-400"><span class="h-1.5 w-1.5 rounded-full bg-emerald-400"></span>Đang hoạt động</div>
          </div>
        </div>
      </div>
    </div>
  </header>
</template>

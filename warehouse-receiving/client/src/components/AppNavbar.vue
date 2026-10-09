<script setup>
import { ref, onMounted, onBeforeUnmount } from 'vue';
import { useRoute } from 'vue-router';
import { Boxes, ChevronDown, Globe } from 'lucide-vue-next';

// Tab co "children" se thanh menu tha xuong. Tab "Nhan hang" active ca khi dang o man hinh quet.
const tabs = [
  { label: 'Nhận hàng', match: '/receiving', children: [
    { label: 'Phiên nhận hàng', to: '/receiving/sessions' },
    { label: 'Hàng đang giữ', to: '/receiving/detained' },
    { label: 'Vị trí kệ', to: '/receiving/bin-locations' },
    { label: 'Định dạng mã tracking', to: '/receiving/tracking-formats' },
  ] },
  { label: 'Danh sách mặt hàng', to: '/items', match: '/items' },
  { label: 'Chuyến bay', match: '/flights', children: [
    { label: 'Quản lý chuyến bay', to: '/flights' },
    { label: 'Chờ vào box', to: '/flights/waiting' },
  ] },
  { label: 'Báo cáo tracking', to: '/reports', match: '/reports' },
];
const route = useRoute();
const isActive = (t) => route.path.startsWith(t.match);
const childActive = (c) => route.path === c.to || (c.to === '/receiving/sessions' && /^\/receiving\/sessions/.test(route.path));


const open = ref(null); // nhan cua menu dang mo
const nav = ref(null);
const onDoc = (e) => { if (nav.value && !nav.value.contains(e.target)) open.value = null; };
onMounted(() => document.addEventListener('click', onDoc));
onBeforeUnmount(() => document.removeEventListener('click', onDoc));
</script>

<template>
  <header class="relative z-30 bg-navy text-white shadow-md">
    <div class="mx-auto flex max-w-[1400px] flex-wrap items-center gap-x-8 gap-y-2 px-4 py-3 sm:px-6">
      <!-- Logo + doi kho -->
      <div class="flex items-center gap-3">
        <div class="flex h-9 w-9 items-center justify-center rounded-lg bg-accent"><Boxes class="h-5 w-5" /></div>
        <div class="leading-tight">
          <div class="text-base font-extrabold tracking-tight">Tina<span class="text-accent">Shipping</span></div>
          <div class="text-xs text-slate-300">OR_1 - Hub Oregon</div>
        </div>
      </div>

      <!-- Tabs -->
      <nav ref="nav" class="order-last flex w-full gap-1 lg:order-none lg:w-auto lg:flex-1">
        <template v-for="t in tabs" :key="t.label">
          <RouterLink v-if="!t.children" :to="t.to"
            class="whitespace-nowrap rounded-md px-4 py-2 text-sm font-medium text-slate-300 transition hover:bg-white/10 hover:text-white"
            :class="{ '!bg-white/15 !text-white shadow-[inset_0_-2px_0_#f97316]': isActive(t) }">
            {{ t.label }}
          </RouterLink>
          <div v-else class="relative">
            <button type="button" data-menu
              class="flex items-center gap-1.5 whitespace-nowrap rounded-md px-4 py-2 text-sm font-medium text-slate-300 transition hover:bg-white/10 hover:text-white"
              :class="{ '!bg-white/15 !text-white shadow-[inset_0_-2px_0_#f97316]': isActive(t) || open === t.label, '!text-accent': open === t.label }"
              @click.stop="open = open === t.label ? null : t.label">
              {{ t.label }}
              <ChevronDown class="h-4 w-4 transition" :class="{ 'rotate-180': open === t.label }" />
            </button>
            <div v-if="open === t.label"
              class="absolute left-0 top-full z-40 mt-2 min-w-[190px] rounded-lg border border-white/10 bg-navy-600 p-1.5 shadow-xl">
              <RouterLink v-for="c in t.children" :key="c.to" :to="c.to" @click="open = null"
                class="block whitespace-nowrap rounded-md px-3.5 py-2.5 text-sm text-slate-200 hover:bg-white/10"
                :class="{ '!bg-white/10 font-semibold !text-accent': childActive(c) }">
                {{ c.label }}
              </RouterLink>
            </div>
          </div>
        </template>
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

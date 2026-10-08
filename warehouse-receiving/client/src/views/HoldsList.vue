<script setup>
import { ref, reactive, computed, watch, onMounted } from 'vue';
import { ArrowLeft, Search, Copy, Check, Plus, X, ChevronDown, ChevronLeft, ChevronRight } from 'lucide-vue-next';
import { api } from '../api';

const REASONS = [
  { v: 'SELLER_RETURN_REQUEST', label: 'Seller return request / Người bán yêu cầu trả hàng' },
  { v: 'CUSTOMER_REQUEST', label: 'Customer request / Khách yêu cầu giữ hàng' },
  { v: 'ADDRESS_ISSUE', label: 'Address issue / Sai hoặc thiếu địa chỉ' },
  { v: 'DOCUMENT_MISSING', label: 'Document missing / Thiếu chứng từ' },
  { v: 'OTHER', label: 'Other / Lý do khác' },
];
const tabs = [
  { v: 'HOLD', label: 'Kho giữ / Hold', key: 'hold', dot: 'bg-slate-700' },
  { v: 'BLOCK', label: 'Khách yêu cầu / Block', key: 'block', dot: 'bg-indigo-400' },
  { v: 'DONE', label: 'Đã xử lý', key: 'done', dot: 'bg-emerald-400' },
];
const presets = [
  { v: 'ALL', label: 'Tất cả' }, { v: 'TODAY', label: 'Hôm nay' }, { v: 'YESTERDAY', label: 'Hôm qua' }, { v: '7D', label: '7 ngày' },
  { v: 'MONTH', label: 'Tháng này' }, { v: 'LASTMONTH', label: 'Tháng trước' }, { v: 'CUSTOM', label: 'Tuỳ chọn' },
];
const ymd = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
function range(p) {
  const n = new Date(), d = (o) => new Date(n.getFullYear(), n.getMonth(), n.getDate() + o);
  if (p === 'TODAY') return [ymd(d(0)), ymd(d(0))];
  if (p === 'YESTERDAY') return [ymd(d(-1)), ymd(d(-1))];
  if (p === '7D') return [ymd(d(-6)), ymd(d(0))];
  if (p === 'MONTH') return [ymd(new Date(n.getFullYear(), n.getMonth(), 1)), ymd(d(0))];
  if (p === 'LASTMONTH') return [ymd(new Date(n.getFullYear(), n.getMonth() - 1, 1)), ymd(new Date(n.getFullYear(), n.getMonth(), 0))];
  return ['', ''];
}

const rows = ref([]);
const counts = ref({ hold: 0, block: 0, done: 0 });
const pagination = ref({ page: 1, limit: 20, total: 0, total_pages: 1 });
const bins = ref([]);
const error = ref('');
const tab = ref('HOLD');
const f = reactive({ search: '', noLoc: false, location: '', preset: 'ALL', from: '', to: '' });
const selected = ref(new Set());

async function load(page = 1) {
  error.value = '';
  try {
    const params = { page, limit: pagination.value.limit, tab: tab.value };
    if (f.search.trim()) params.search = f.search.trim();
    if (f.noLoc) params.no_location = '1'; else if (f.location) params.location = f.location;
    const [from, to] = f.preset === 'CUSTOM' ? [f.from, f.to] : range(f.preset);
    if (from) params.from = from; if (to) params.to = to;
    const r = await api.listHolds(params);
    rows.value = r.data; counts.value = r.counts; pagination.value = r.pagination; selected.value = new Set();
  } catch (e) { error.value = e.message; }
}
async function loadBins() { try { bins.value = (await api.listBins()).data; } catch { /* bo qua */ } }
watch(tab, () => load(1));
watch(() => [f.noLoc, f.location, f.preset, f.from, f.to], () => load(1));
watch(() => pagination.value.limit, () => load(1));
onMounted(() => { load(); loadBins(); });

const fmt = (v) => { const d = new Date(v), p = (n) => String(n).padStart(2, '0'); return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`; };
const copied = ref('');
async function copy(t) { try { await navigator.clipboard.writeText(t); } catch { /* bo qua */ } copied.value = t; setTimeout(() => { if (copied.value === t) copied.value = ''; }, 1200); }

// Chon nhieu dong
const allChecked = computed(() => rows.value.length > 0 && rows.value.every((r) => selected.value.has(r.id)));
function toggleAll() { selected.value = allChecked.value ? new Set() : new Set(rows.value.map((r) => r.id)); }
function toggle(id) { const s = new Set(selected.value); s.has(id) ? s.delete(id) : s.add(id); selected.value = s; }
const bulkLoc = ref('');
async function bulk(action) {
  try {
    await api.bulkHolds({ ids: [...selected.value], action, bin_location_id: bulkLoc.value || null });
    bulkLoc.value = ''; await load(pagination.value.page);
  } catch (e) { error.value = e.message; }
}

// Them moi
const showAdd = ref(false);
const form = reactive({});
const formError = ref('');
function openAdd() { Object.assign(form, { tracking_code: '', hold_type: tab.value === 'BLOCK' ? 'CUSTOMER' : 'WAREHOUSE', reason_code: REASONS[0].v, reason: REASONS[0].label, bin_location_id: '' }); formError.value = ''; showAdd.value = true; }
watch(() => form.reason_code, (c) => { const r = REASONS.find((x) => x.v === c); if (r && showAdd.value) form.reason = r.label; });
async function create() {
  formError.value = '';
  try { await api.createHold({ ...form }); showAdd.value = false; tab.value = form.hold_type === 'CUSTOMER' ? 'BLOCK' : 'HOLD'; await load(1); }
  catch (e) { formError.value = e.message; }
}

// Chi tiet
const detail = ref(null);
const dLoc = ref('');
const dError = ref('');
function openDetail(r) { detail.value = r; dLoc.value = r.bin_location_id || ''; dError.value = ''; }
async function dSave(body) {
  try { await api.patchHold(detail.value.id, body); detail.value = null; await load(pagination.value.page); } catch (e) { dError.value = e.message; }
}
async function dDelete() {
  if (!confirm('Xóa bản ghi giữ hàng này?')) return;
  try { await api.deleteHold(detail.value.id); detail.value = null; await load(pagination.value.page); } catch (e) { dError.value = e.message; }
}
</script>

<template>
  <div>
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div>
        <RouterLink to="/receiving/sessions" class="btn-outline mb-4 !border-navy !text-navy"><span class="flex h-5 w-5 items-center justify-center rounded bg-navy text-white"><ArrowLeft class="h-3.5 w-3.5" /></span> Quay lại · Phiên nhận hàng</RouterLink>
        <h1 class="border-l-4 border-navy pl-3 text-2xl font-extrabold text-slate-900">Hàng đang giữ</h1>
        <p class="mt-1 mb-4 text-sm text-slate-500">Kiện chưa được bay — kho giữ hoặc khách yêu cầu.</p>
      </div>
      <button class="btn-accent mt-14" @click="openAdd"><Plus class="h-4 w-4" /> Thêm hàng giữ</button>
    </div>

    <div class="card overflow-hidden">
      <div class="flex gap-1 border-b border-slate-200 bg-slate-50 px-3">
        <button v-for="t in tabs" :key="t.v" @click="tab = t.v" class="flex items-center gap-2 border-b-2 px-4 py-3 text-sm font-medium transition"
          :class="tab === t.v ? 'border-navy bg-white text-slate-900' : 'border-transparent text-slate-600 hover:text-slate-900'">
          <span class="h-2 w-2 rounded-full" :class="t.dot"></span>{{ t.label }}<span v-if="tab === t.v || counts[t.key]" class="font-bold">{{ counts[t.key] }}</span>
        </button>
      </div>

      <div class="flex flex-wrap items-center gap-2 p-3">
        <div class="flex">
          <input v-model="f.search" class="input h-9 w-44 rounded-r-none" placeholder="Mã kiện" @keyup.enter="load(1)" />
          <button class="btn-outline h-9 rounded-l-none border-l-0 px-3" @click="load(1)"><Search class="h-4 w-4" /></button>
        </div>
        <label class="flex cursor-pointer items-center gap-1.5 rounded border border-slate-300 bg-white px-2.5 py-2 text-sm"><input v-model="f.noLoc" type="checkbox" /> Chưa có vị trí</label>
        <div class="relative">
          <select v-model="f.location" :disabled="f.noLoc" class="input h-9 w-44 cursor-pointer appearance-none pr-8 disabled:opacity-50" :class="{ 'text-slate-400': !f.location }">
            <option value="">Vị trí</option><option v-for="b in bins" :key="b.id" :value="b.id" class="text-slate-800">{{ b.code }}</option>
          </select>
          <ChevronDown class="pointer-events-none absolute right-2.5 top-2.5 h-4 w-4 text-slate-400" />
        </div>
        <div class="flex rounded-lg bg-slate-100 p-0.5 text-sm">
          <button v-for="p in presets" :key="p.v" class="rounded-md px-3 py-1.5" :class="f.preset === p.v ? 'bg-white font-medium shadow-sm' : 'text-slate-600 hover:text-slate-900'" @click="f.preset = p.v">{{ p.label }}</button>
        </div>
        <template v-if="f.preset === 'CUSTOM'">
          <input v-model="f.from" type="date" class="input h-9 w-36" /><span class="text-slate-400">→</span><input v-model="f.to" type="date" class="input h-9 w-36" />
        </template>
      </div>

      <div v-if="selected.size" class="flex flex-wrap items-center gap-2 border-y border-amber-200 bg-amber-50 px-4 py-2 text-sm">
        <b>Đã chọn {{ selected.size }} kiện</b>
        <select v-model="bulkLoc" class="input h-8 w-44 py-0"><option value="">— Vị trí —</option><option v-for="b in bins" :key="b.id" :value="b.id">{{ b.code }}</option></select>
        <button class="btn-outline h-8 px-3" :disabled="!bulkLoc" @click="bulk('assign')">Gán vị trí</button>
        <button v-if="tab !== 'DONE'" class="btn-navy h-8 px-3" @click="bulk('resolve')">Đánh dấu đã xử lý</button>
      </div>
      <p v-if="error" class="px-4 py-2 text-sm text-red-600">{{ error }}</p>

      <div class="overflow-x-auto">
        <table class="w-full min-w-[900px] text-sm">
          <thead><tr class="bg-slate-100 text-left text-sm font-bold text-slate-800">
            <th class="w-10 px-3 py-2"><input type="checkbox" :checked="allChecked" @change="toggleAll" /></th>
            <th class="px-2 py-2">Mã tracking</th><th class="px-2 py-2">Mã vụ</th><th class="px-2 py-2">Lý do giữ</th>
            <th class="px-2 py-2">Vị trí</th><th class="px-2 py-2">{{ tab === 'DONE' ? 'Xử lý lúc' : 'Mở lúc' }}</th><th class="w-24"></th>
          </tr></thead>
          <tbody>
            <tr v-for="r in rows" :key="r.id" class="border-b border-slate-100 hover:bg-slate-50">
              <td class="px-3 py-2"><input type="checkbox" :checked="selected.has(r.id)" @change="toggle(r.id)" /></td>
              <td class="px-2 py-2"><span class="flex items-center gap-1.5 font-mono font-bold text-slate-900">{{ r.tracking_code }}
                <button class="text-slate-500 hover:text-navy" title="Sao chép" @click="copy(r.tracking_code)"><Check v-if="copied === r.tracking_code" class="h-3.5 w-3.5 text-emerald-600" /><Copy v-else class="h-3.5 w-3.5" /></button></span></td>
              <td class="px-2 py-2 text-slate-400">{{ r.hold_code }}</td>
              <td class="px-2 py-2">{{ r.reason }}</td>
              <td class="px-2 py-2"><span v-if="r.location_code" class="rounded bg-slate-100 px-2 py-0.5 font-mono text-xs font-bold">{{ r.location_code }}</span></td>
              <td class="px-2 py-2 text-slate-700">{{ fmt(tab === 'DONE' ? r.resolved_at : r.opened_at) }}</td>
              <td class="px-2 py-2"><button class="rounded border border-slate-300 px-3 py-1 text-sm hover:border-accent hover:text-accent" @click="openDetail(r)">Chi tiết</button></td>
            </tr>
            <tr v-if="!rows.length"><td colspan="7" class="py-14 text-center text-slate-400">Không có kiện nào.</td></tr>
          </tbody>
        </table>
      </div>
      <div class="flex items-center justify-end gap-3 px-4 py-3 text-sm text-slate-600">
        <button class="btn-outline px-2 py-1" :disabled="pagination.page <= 1" @click="load(pagination.page - 1)"><ChevronLeft class="h-4 w-4" /></button>
        <span class="rounded border border-navy px-3 py-1 font-semibold text-slate-900">{{ pagination.page }}</span>
        <button class="btn-outline px-2 py-1" :disabled="pagination.page >= pagination.total_pages" @click="load(pagination.page + 1)"><ChevronRight class="h-4 w-4" /></button>
        <select v-model.number="pagination.limit" class="input w-auto py-1.5"><option :value="20">20 / trang</option><option :value="50">50 / trang</option><option :value="100">100 / trang</option></select>
      </div>
    </div>

    <!-- Them -->
    <div v-if="showAdd" class="fixed inset-0 z-40 flex items-start justify-center overflow-y-auto bg-black/50 p-4" @mousedown.self="showAdd = false">
      <form class="card my-8 w-full max-w-lg p-6" @submit.prevent="create">
        <div class="mb-4 flex items-center justify-between"><h2 class="text-lg font-bold">Thêm hàng giữ</h2><button type="button" class="text-slate-400 hover:text-slate-700" @click="showAdd = false"><X class="h-5 w-5" /></button></div>
        <div class="grid gap-3">
          <label class="block text-sm font-medium text-slate-700">Mã tracking *<input v-model="form.tracking_code" class="input mt-1 font-mono" maxlength="100" /></label>
          <label class="block text-sm font-medium text-slate-700">Loại<select v-model="form.hold_type" class="input mt-1"><option value="WAREHOUSE">Kho giữ / Hold</option><option value="CUSTOMER">Khách yêu cầu / Block</option></select></label>
          <label class="block text-sm font-medium text-slate-700">Lý do<select v-model="form.reason_code" class="input mt-1"><option v-for="r in REASONS" :key="r.v" :value="r.v">{{ r.label }}</option></select></label>
          <label class="block text-sm font-medium text-slate-700">Ghi chú lý do<input v-model="form.reason" class="input mt-1" maxlength="300" /></label>
          <label class="block text-sm font-medium text-slate-700">Vị trí kệ<select v-model="form.bin_location_id" class="input mt-1"><option value="">— Chưa có vị trí —</option><option v-for="b in bins" :key="b.id" :value="b.id">{{ b.code }}</option></select></label>
        </div>
        <p v-if="formError" class="mt-3 text-sm text-red-600">{{ formError }}</p>
        <div class="mt-5 flex justify-end gap-2"><button type="button" class="btn-outline" @click="showAdd = false">Hủy</button><button class="btn-accent">Thêm</button></div>
      </form>
    </div>

    <!-- Chi tiet -->
    <div v-if="detail" class="fixed inset-0 z-40 flex items-start justify-center overflow-y-auto bg-black/50 p-4" @mousedown.self="detail = null">
      <div class="card my-8 w-full max-w-lg p-6">
        <div class="mb-4 flex items-center justify-between"><h2 class="text-lg font-bold">Chi tiết hàng giữ</h2><button class="text-slate-400 hover:text-slate-700" @click="detail = null"><X class="h-5 w-5" /></button></div>
        <dl class="grid grid-cols-[110px_1fr] gap-y-2 text-sm">
          <dt class="text-slate-500">Mã tracking</dt><dd class="font-mono font-bold">{{ detail.tracking_code }}</dd>
          <dt class="text-slate-500">Mã vụ</dt><dd class="break-all text-slate-700">{{ detail.hold_code }}</dd>
          <dt class="text-slate-500">Loại</dt><dd>{{ detail.hold_type === 'CUSTOMER' ? 'Khách yêu cầu / Block' : 'Kho giữ / Hold' }}</dd>
          <dt class="text-slate-500">Lý do</dt><dd>{{ detail.reason || '—' }}</dd>
          <dt class="text-slate-500">Mở lúc</dt><dd>{{ fmt(detail.opened_at) }}</dd>
          <dt class="text-slate-500">Trạng thái</dt><dd>{{ detail.status === 'RESOLVED' ? 'Đã xử lý lúc ' + fmt(detail.resolved_at) : 'Đang giữ' }}</dd>
          <dt class="self-center text-slate-500">Vị trí kệ</dt>
          <dd class="flex gap-2"><select v-model="dLoc" class="input h-9 py-0"><option value="">— Chưa có vị trí —</option><option v-for="b in bins" :key="b.id" :value="b.id">{{ b.code }}</option></select>
            <button class="btn-outline h-9 px-3" @click="dSave({ bin_location_id: dLoc || null })">Lưu</button></dd>
        </dl>
        <p v-if="dError" class="mt-3 text-sm text-red-600">{{ dError }}</p>
        <div class="mt-5 flex items-center justify-between">
          <button class="btn-outline !border-red-200 !text-red-600 hover:!bg-red-50" @click="dDelete">Xóa</button>
          <button v-if="detail.status === 'ACTIVE'" class="btn-navy" @click="dSave({ status: 'RESOLVED' })">Đánh dấu đã xử lý</button>
          <button v-else class="btn-outline" @click="dSave({ status: 'ACTIVE' })">Mở lại</button>
        </div>
      </div>
    </div>
  </div>
</template>

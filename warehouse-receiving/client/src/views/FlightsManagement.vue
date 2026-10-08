<script setup>
import { ref, reactive, computed, watch, onMounted } from 'vue';
import { Search, Plus, X, Eye, XCircle, ChevronDown, ChevronRight, ChevronLeft, Minus, SlidersHorizontal, LayoutGrid, Package, Plane, ArrowRight } from 'lucide-vue-next';
import { api } from '../api';

const AIRLINES = [
  { code: 'CHINA_AIRLINES', name: 'China Airlines' },
  { code: 'EVA', name: 'EVA Air' },
  { code: 'VIETNAM_AIRLINES', name: 'Vietnam Airlines' },
  { code: 'KOREAN_AIR', name: 'Korean Air' },
  { code: 'CATHAY_PACIFIC', name: 'Cathay Pacific' },
  { code: 'ANA', name: 'All Nippon Airways' },
];
const MODES = [{ v: 'INFORMAL', label: 'Tiểu ngạch' }, { v: 'FORMAL', label: 'Chính ngạch' }];
const STATUS = {
  OPEN: { label: 'Đang mở (Gom hàng)', cls: 'border-sky-400 bg-sky-50 text-sky-700' },
  ARRIVED: { label: 'Đã đến VN', cls: 'border-emerald-400 bg-emerald-50 text-emerald-700' },
  CLOSED: { label: 'Đã đóng chuyến', cls: 'border-slate-300 bg-slate-100 text-slate-600' },
};
const DATE_FIELDS = [{ v: 'created', label: 'Ngày tạo' }, { v: 'etd', label: 'ETD' }, { v: 'eta', label: 'ETA' }];
const tabs = [
  { v: 'ALL', label: 'Tất cả', key: 'all', icon: LayoutGrid },
  { v: 'OPEN', label: 'Đang gom', key: 'open', icon: Package },
  { v: 'CLOSED', label: 'Đã đóng chuyến', key: 'closed', icon: Plane },
];

// ---------- Danh sach + bo loc ----------
const rows = ref([]);
const counts = ref({ all: 0, open: 0, closed: 0 });
const pagination = ref({ page: 1, limit: 20, total: 0, total_pages: 1 });
const loading = ref(false);
const error = ref('');
const tab = ref('ALL');
const showAdvanced = ref(false);
const blankFilter = () => ({ search: '', airline: '', mode: '', date_field: '', from: '', to: '', origin: '', destination: '', status: '' });
const filter = reactive(blankFilter());
const applied = ref(blankFilter());

async function load(page = 1) {
  loading.value = true; error.value = '';
  try {
    const params = { page, limit: pagination.value.limit, tab: tab.value };
    for (const [k, v] of Object.entries(applied.value)) if (v) params[k] = v;
    const res = await api.listFlights(params);
    rows.value = res.data; counts.value = res.counts; pagination.value = res.pagination;
    expanded.value = new Set();
  } catch (e) { error.value = e.message; } finally { loading.value = false; }
}
function apply() { applied.value = { ...filter }; load(1); }
function clearFilter() { Object.assign(filter, blankFilter()); apply(); }
// Chon loai ngay / khoang ngay / select la loc ngay; o tim kiem can Enter
watch(() => [filter.airline, filter.mode, filter.date_field, filter.from, filter.to, filter.status], apply);
watch(tab, () => load(1));
watch(() => pagination.value.limit, () => load(1));
onMounted(() => load());

const expanded = ref(new Set());
function toggleRow(id) {
  const s = new Set(expanded.value);
  s.has(id) ? s.delete(id) : s.add(id);
  expanded.value = s;
}

const fmt = (v) => {
  if (!v) return '';
  const d = new Date(v), p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
};
const toInput = (v) => fmt(v).replace(' ', 'T'); // gia tri cho <input type=datetime-local>
const modeLabel = (m) => MODES.find((x) => x.v === m)?.label;

// ---------- Form tao / xem-sua ----------
const showForm = ref(false);
const editingId = ref(null);
const form = reactive({});
const saving = ref(false);
const formError = ref('');
const blank = () => ({ name: '', mawb: '', airline_code: '', origin: '', destination: '', transport_mode: 'INFORMAL', etd: '', eta: '', box_count: 0, hawb_count: 0, note: '', status: 'OPEN' });
function openAdd() { editingId.value = null; Object.assign(form, blank()); formError.value = ''; showForm.value = true; }
function openEdit(r) {
  editingId.value = r.id;
  Object.assign(form, blank(), r, { airline_code: r.airline_code || '', etd: toInput(r.etd), eta: toInput(r.eta), mawb: r.mawb || '', origin: r.origin || '', destination: r.destination || '', note: r.note || '' });
  formError.value = ''; showForm.value = true;
}
async function save() {
  formError.value = '';
  if (!form.name.trim()) { formError.value = 'Vui lòng nhập tên chuyến bay'; return; }
  const al = AIRLINES.find((a) => a.code === form.airline_code);
  const body = { ...form, airline_name: al?.name || null, airline_code: form.airline_code || null, etd: form.etd || null, eta: form.eta || null };
  saving.value = true;
  try {
    if (editingId.value) await api.updateFlight(editingId.value, body); else await api.createFlight(body);
    showForm.value = false; await load(editingId.value ? pagination.value.page : 1);
  } catch (e) { formError.value = e.message; } finally { saving.value = false; }
}
async function removeFlight() {
  if (!confirm('Xóa chuyến bay này?')) return;
  try { await api.deleteFlight(editingId.value); showForm.value = false; await load(pagination.value.page); }
  catch (e) { formError.value = e.message; }
}

// ---------- Dong chuyen ----------
const closing = ref(null);
const closeError = ref('');
async function confirmClose() {
  try { await api.setFlightStatus(closing.value.id, 'CLOSED'); closing.value = null; await load(pagination.value.page); }
  catch (e) { closeError.value = e.message; }
}
</script>

<template>
  <div>
    <div class="mb-5 flex flex-wrap items-start justify-between gap-3">
      <div>
        <h1 class="border-l-4 border-navy pl-3 text-2xl font-extrabold text-slate-900">Quản lý chuyến bay</h1>
        <p class="mt-1 text-sm text-slate-500">Theo dõi chuyến bay gom hàng, chứng từ và trạng thái vận chuyển từ lúc gom kiện đến khi hàng về Việt Nam.</p>
      </div>
      <button class="btn-navy" @click="openAdd"><Plus class="h-4 w-4" /> Tạo chuyến bay mới</button>
    </div>

    <!-- Tab trang thai -->
    <div class="mb-4 flex gap-1 border-b border-slate-200">
      <button v-for="t in tabs" :key="t.v" @click="tab = t.v"
        class="-mb-px flex items-center gap-2 border-b-2 px-4 py-3 text-base font-bold transition"
        :class="tab === t.v ? 'border-accent text-slate-900' : 'border-transparent text-slate-500 hover:text-slate-900'">
        <component :is="t.icon" class="h-4 w-4" />{{ t.label }}
        <span class="rounded-full bg-slate-200 px-2 py-0.5 text-xs font-semibold text-slate-600">{{ counts[t.key] }}</span>
      </button>
    </div>

    <!-- Loc va tim kiem -->
    <div class="card mb-4 p-5">
      <h2 class="mb-3 text-base font-bold text-slate-900">Lọc và Tìm kiếm</h2>
      <div class="flex flex-wrap items-center gap-2">
        <div class="flex">
          <input v-model="filter.search" class="input h-10 w-52 rounded-r-none" placeholder="Tên chuyến hoặc MA…" @keyup.enter="apply" />
          <button class="btn-outline h-10 rounded-l-none border-l-0 px-3" title="Tìm kiếm" @click="apply"><Search class="h-4 w-4" /></button>
        </div>
        <div class="relative">
          <select v-model="filter.airline" class="input h-10 w-40 cursor-pointer appearance-none pr-8" :class="{ 'text-slate-400': !filter.airline }">
            <option value="">Hãng hàng không</option>
            <option v-for="a in AIRLINES" :key="a.code" :value="a.code" class="text-slate-800">{{ a.name }}</option>
          </select>
          <ChevronDown class="pointer-events-none absolute right-2.5 top-3 h-4 w-4 text-slate-400" />
        </div>
        <div class="relative">
          <select v-model="filter.mode" class="input h-10 w-32 cursor-pointer appearance-none pr-8" :class="{ 'text-slate-400': !filter.mode }">
            <option value="">Hình thức</option>
            <option v-for="m in MODES" :key="m.v" :value="m.v" class="text-slate-800">{{ m.label }}</option>
          </select>
          <ChevronDown class="pointer-events-none absolute right-2.5 top-3 h-4 w-4 text-slate-400" />
        </div>
        <div class="relative">
          <select v-model="filter.date_field" class="input h-10 w-36 cursor-pointer appearance-none pr-8" :class="{ 'text-slate-400': !filter.date_field }">
            <option value="">Loại ngày</option>
            <option v-for="d in DATE_FIELDS" :key="d.v" :value="d.v" class="text-slate-800">{{ d.label }}</option>
          </select>
          <ChevronDown class="pointer-events-none absolute right-2.5 top-3 h-4 w-4 text-slate-400" />
        </div>
        <div class="flex h-10 items-center gap-2 rounded-lg border border-slate-300 bg-white px-3 text-sm">
          <input v-model="filter.from" type="date" class="w-[7.6rem] bg-transparent outline-none" title="Ngày bắt đầu" />
          <ArrowRight class="h-3.5 w-3.5 text-slate-400" />
          <input v-model="filter.to" type="date" class="w-[7.6rem] bg-transparent outline-none" title="Ngày kết thúc" />
        </div>
        <button class="btn-outline h-10" :class="{ '!border-accent !text-accent': showAdvanced }" @click="showAdvanced = !showAdvanced">
          <SlidersHorizontal class="h-4 w-4" /> Bộ lọc nâng cao
        </button>
        <button class="btn-outline h-10" @click="clearFilter">Xoá lọc</button>
      </div>

      <div v-if="showAdvanced" class="mt-3 flex flex-wrap items-center gap-2 border-t border-slate-100 pt-3">
        <input v-model="filter.origin" class="input h-10 w-48 uppercase" maxlength="10" placeholder="Sân bay đi (PDX)" @keyup.enter="apply" />
        <input v-model="filter.destination" class="input h-10 w-52 uppercase" maxlength="10" placeholder="Sân bay đến (HAN)" @keyup.enter="apply" />
        <div class="relative">
          <select v-model="filter.status" class="input h-10 w-52 cursor-pointer appearance-none pr-8" :class="{ 'text-slate-400': !filter.status }">
            <option value="">Trạng thái</option>
            <option v-for="(s, k) in STATUS" :key="k" :value="k" class="text-slate-800">{{ s.label }}</option>
          </select>
          <ChevronDown class="pointer-events-none absolute right-2.5 top-3 h-4 w-4 text-slate-400" />
        </div>
        <button class="btn-accent h-10" @click="apply">Áp dụng</button>
      </div>
    </div>

    <p v-if="error" class="mb-3 text-sm text-red-600">{{ error }}</p>

    <!-- Bang -->
    <div class="card overflow-hidden">
      <div class="overflow-x-auto">
        <table class="w-full min-w-[1080px] text-sm">
          <thead>
            <tr class="bg-navy text-center text-xs font-bold text-white">
              <th class="w-12 px-2 py-3"></th>
              <th class="px-3 py-3">Chuyến bay / MAWB</th>
              <th class="px-3 py-3">Tuyến / Hình thức</th>
              <th class="px-3 py-3">Trạng thái</th>
              <th class="px-3 py-3">ETD / ETA</th>
              <th class="w-28 px-3 py-3">Thùng / HAWB</th>
              <th class="w-36 px-3 py-3">Ngày tạo</th>
              <th class="w-28 px-3 py-3">Thao tác</th>
            </tr>
          </thead>
          <tbody>
            <template v-for="r in rows" :key="r.id">
              <tr class="border-b border-slate-100 text-center align-middle hover:bg-slate-50/70">
                <td class="px-2 py-4">
                  <button class="flex h-6 w-6 items-center justify-center rounded border border-slate-300 text-slate-600 hover:border-accent hover:text-accent"
                    :title="expanded.has(r.id) ? 'Thu gọn' : 'Mở rộng'" @click="toggleRow(r.id)">
                    <Minus v-if="expanded.has(r.id)" class="h-3.5 w-3.5" /><Plus v-else class="h-3.5 w-3.5" />
                  </button>
                </td>
                <td class="px-3 py-4">
                  <div class="text-[15px] font-bold text-slate-900">{{ r.name }}</div>
                  <div class="mt-1.5"><span class="inline-block rounded bg-slate-100 px-2.5 py-0.5 text-xs text-slate-700">MAWB · {{ r.mawb || '—' }}</span></div>
                  <div v-if="r.airline_name" class="mt-1.5 text-slate-500">{{ r.airline_code }} - {{ r.airline_name }}</div>
                </td>
                <td class="px-3 py-4">
                  <div class="font-medium text-slate-800">{{ r.origin || '—' }} <span class="text-slate-400">→</span> {{ r.destination || '—' }}</div>
                  <span class="mt-1.5 inline-block rounded px-2 py-0.5 text-xs"
                    :class="r.transport_mode === 'FORMAL' ? 'bg-violet-50 text-violet-700' : 'bg-amber-50 text-amber-700'">{{ modeLabel(r.transport_mode) }}</span>
                </td>
                <td class="px-3 py-4">
                  <span class="inline-block rounded border px-2.5 py-1 text-xs font-medium" :class="STATUS[r.status].cls">{{ STATUS[r.status].label }}</span>
                </td>
                <td class="px-3 py-4 text-left">
                  <div class="flex items-center gap-2"><span class="rounded bg-sky-50 px-1.5 py-0.5 text-[11px] font-bold text-sky-700">ETD</span>{{ fmt(r.etd) || '—' }}</div>
                  <div class="mt-1.5 flex items-center gap-2"><span class="rounded bg-emerald-50 px-1.5 py-0.5 text-[11px] font-bold text-emerald-700">ETA</span>{{ fmt(r.eta) || '—' }}</div>
                </td>
                <td class="px-3 py-4 text-base text-slate-800">{{ r.box_count }} / {{ r.hawb_count }}</td>
                <td class="px-3 py-4 text-slate-700">{{ fmt(r.created_at) }}</td>
                <td class="px-3 py-4">
                  <div class="flex items-center justify-center gap-3">
                    <button class="text-navy hover:text-accent" title="Xem / sửa" @click="openEdit(r)"><Eye class="h-5 w-5" /></button>
                    <button v-if="r.status === 'OPEN'" class="text-slate-700 hover:text-red-600" title="Đóng chuyến" @click="closeError = ''; closing = r"><XCircle class="h-5 w-5" /></button>
                  </div>
                </td>
              </tr>
              <tr v-if="expanded.has(r.id)" class="border-b border-slate-100 bg-slate-50">
                <td></td>
                <td colspan="7" class="px-3 py-4">
                  <div class="grid gap-x-8 gap-y-2 text-sm sm:grid-cols-2 lg:grid-cols-4">
                    <div><span class="text-slate-500">Hãng bay:</span> <b>{{ r.airline_name || '—' }}</b></div>
                    <div><span class="text-slate-500">Tuyến:</span> <b>{{ r.origin || '—' }} → {{ r.destination || '—' }}</b></div>
                    <div><span class="text-slate-500">Số thùng:</span> <b>{{ r.box_count }}</b></div>
                    <div><span class="text-slate-500">Số HAWB:</span> <b>{{ r.hawb_count }}</b></div>
                    <div class="sm:col-span-2 lg:col-span-4"><span class="text-slate-500">Ghi chú:</span> {{ r.note || '—' }}</div>
                  </div>
                </td>
              </tr>
            </template>
            <tr v-if="!rows.length">
              <td colspan="8" class="px-4 py-16 text-center text-slate-400">
                {{ loading ? 'Đang tải…' : 'Chưa có chuyến bay nào. Bấm “Tạo chuyến bay mới” để thêm.' }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- Phan trang -->
      <div class="flex flex-wrap items-center justify-end gap-3 border-t border-slate-200 px-4 py-3 text-sm text-slate-600">
        <span>Tổng {{ pagination.total }} chuyến bay</span>
        <button class="btn-outline px-2 py-1" :disabled="pagination.page <= 1" @click="load(pagination.page - 1)"><ChevronLeft class="h-4 w-4" /></button>
        <span class="rounded border border-navy px-3 py-1 font-semibold text-slate-900">{{ pagination.page }}</span>
        <button class="btn-outline px-2 py-1" :disabled="pagination.page >= pagination.total_pages" @click="load(pagination.page + 1)"><ChevronRight class="h-4 w-4" /></button>
        <select v-model.number="pagination.limit" class="input w-auto py-1.5"><option :value="20">20 / trang</option><option :value="50">50 / trang</option><option :value="100">100 / trang</option></select>
      </div>
    </div>

    <!-- Form tao / xem-sua -->
    <div v-if="showForm" class="fixed inset-0 z-40 flex items-start justify-center overflow-y-auto bg-black/50 p-4" @mousedown.self="showForm = false">
      <form class="card my-8 w-full max-w-2xl p-6" @submit.prevent="save">
        <div class="mb-4 flex items-center justify-between">
          <h2 class="text-lg font-bold text-slate-900">{{ editingId ? 'Chi tiết chuyến bay' : 'Tạo chuyến bay mới' }}</h2>
          <button type="button" class="text-slate-400 hover:text-slate-700" @click="showForm = false"><X class="h-5 w-5" /></button>
        </div>
        <div class="grid gap-4 sm:grid-cols-2">
          <label class="block text-sm font-medium text-slate-700 sm:col-span-2">Tên chuyến bay *
            <input v-model="form.name" class="input mt-1" maxlength="200" placeholder="VD: HONGPHAT-8899-HAN" />
          </label>
          <label class="block text-sm font-medium text-slate-700">MAWB
            <input v-model="form.mawb" class="input mt-1 font-mono" maxlength="50" placeholder="695-57531977" />
          </label>
          <label class="block text-sm font-medium text-slate-700">Hãng hàng không
            <select v-model="form.airline_code" class="input mt-1"><option value="">— Chọn —</option><option v-for="a in AIRLINES" :key="a.code" :value="a.code">{{ a.name }}</option></select>
          </label>
          <label class="block text-sm font-medium text-slate-700">Sân bay đi
            <input v-model="form.origin" class="input mt-1 uppercase" maxlength="10" placeholder="PDX" />
          </label>
          <label class="block text-sm font-medium text-slate-700">Sân bay đến
            <input v-model="form.destination" class="input mt-1 uppercase" maxlength="10" placeholder="HAN" />
          </label>
          <label class="block text-sm font-medium text-slate-700">Hình thức
            <select v-model="form.transport_mode" class="input mt-1"><option v-for="m in MODES" :key="m.v" :value="m.v">{{ m.label }}</option></select>
          </label>
          <label v-if="editingId" class="block text-sm font-medium text-slate-700">Trạng thái
            <select v-model="form.status" class="input mt-1" disabled><option v-for="(s, k) in STATUS" :key="k" :value="k">{{ s.label }}</option></select>
          </label>
          <label class="block text-sm font-medium text-slate-700">ETD (dự kiến khởi hành)
            <input v-model="form.etd" type="datetime-local" class="input mt-1" />
          </label>
          <label class="block text-sm font-medium text-slate-700">ETA (dự kiến đến)
            <input v-model="form.eta" type="datetime-local" class="input mt-1" />
          </label>
          <label class="block text-sm font-medium text-slate-700">Số thùng
            <input v-model.number="form.box_count" type="number" min="0" class="input mt-1" />
          </label>
          <label class="block text-sm font-medium text-slate-700">Số HAWB
            <input v-model.number="form.hawb_count" type="number" min="0" class="input mt-1" />
          </label>
          <label class="block text-sm font-medium text-slate-700 sm:col-span-2">Ghi chú
            <textarea v-model="form.note" rows="2" maxlength="500" class="input mt-1"></textarea>
          </label>
        </div>
        <p v-if="formError" class="mt-3 text-sm text-red-600">{{ formError }}</p>
        <div class="mt-5 flex items-center justify-between gap-2">
          <button v-if="editingId" type="button" class="btn-outline !border-red-200 !text-red-600 hover:!bg-red-50" @click="removeFlight">Xóa chuyến</button>
          <span v-else></span>
          <div class="flex gap-2">
            <button type="button" class="btn-outline" @click="showForm = false">Hủy</button>
            <button class="btn-accent" :disabled="saving">{{ saving ? 'Đang lưu…' : editingId ? 'Lưu thay đổi' : 'Tạo chuyến bay' }}</button>
          </div>
        </div>
      </form>
    </div>

    <!-- Xac nhan dong chuyen -->
    <div v-if="closing" class="fixed inset-0 z-40 flex items-center justify-center bg-black/50 p-4" @mousedown.self="closing = null">
      <div class="card w-full max-w-md p-6">
        <h2 class="text-lg font-bold text-slate-900">Đóng chuyến bay?</h2>
        <p class="mt-2 text-sm text-slate-600">Chuyến <b>{{ closing.name }}</b> sẽ chuyển sang “Đã đóng chuyến” và không gom thêm hàng.</p>
        <p v-if="closeError" class="mt-2 text-sm text-red-600">{{ closeError }}</p>
        <div class="mt-5 flex justify-end gap-2">
          <button class="btn-outline" @click="closing = null">Hủy</button>
          <button class="btn-navy" @click="confirmClose">Đóng chuyến</button>
        </div>
      </div>
    </div>
  </div>
</template>

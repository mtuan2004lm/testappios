<script setup>
import { ref, reactive, computed, watch, onMounted } from 'vue';
import { Search, Copy, Eye, ChevronLeft, ChevronRight, ChevronDown, Plus, X, ImagePlus, Trash2, Image as ImageIcon, Check } from 'lucide-vue-next';
import { api } from '../api';

// ---------- Danh sach ----------
const rows = ref([]);
const pagination = ref({ page: 1, limit: 20, total: 0, total_pages: 1 });
const loading = ref(false);
const error = ref('');

const field = ref('tracking');
const fields = [
  { v: 'tracking', label: 'Mã tracking', ph: 'Dán nguyên mã tracking' },
  { v: 'order', label: 'Mã đơn hàng', ph: 'Nhập mã đơn hàng' },
  { v: 'name', label: 'Tên hàng', ph: 'Nhập tên hàng' },
  { v: 'partner', label: 'Đối tác', ph: 'Nhập tên đối tác' },
];
const placeholder = computed(() => fields.find((f) => f.v === field.value).ph);
const keyword = ref('');
const applied = reactive({ field: 'tracking', search: '' });
const tab = ref('ALL');
const tabs = [
  { v: 'ALL', label: 'Tất cả', dot: 'bg-slate-700' },
  { v: 'UNFILTERED', label: 'Chưa dịch lọc', dot: 'bg-blue-400' },
  { v: 'FILTERED', label: 'Dịch lọc', dot: 'bg-emerald-400' },
];
const limits = [20, 50, 100];

async function load(page = 1) {
  loading.value = true; error.value = '';
  try {
    const params = { page, limit: pagination.value.limit, field: applied.field };
    if (applied.search) params.search = applied.search;
    if (tab.value !== 'ALL') params.filter = tab.value;
    const res = await api.listProducts(params);
    rows.value = res.data; pagination.value = res.pagination;
  } catch (e) { error.value = e.message; } finally { loading.value = false; }
}
function doSearch() { applied.field = field.value; applied.search = keyword.value.trim(); load(1); }
function clearSearch() { keyword.value = ''; applied.search = ''; load(1); }
function searchBy(f, value) { field.value = f; keyword.value = value; doSearch(); }
watch(tab, () => load(1));
watch(() => pagination.value.limit, () => load(1));
onMounted(() => load());

const copied = ref('');
async function copy(text) {
  try { await navigator.clipboard.writeText(text); } catch { /* bo qua */ }
  copied.value = text; setTimeout(() => { if (copied.value === text) copied.value = ''; }, 1200);
}
const stt = (i) => (pagination.value.page - 1) * pagination.value.limit + i + 1;

// ---------- Form them / sua ----------
const showForm = ref(false);
const editingId = ref(null);
const form = reactive({});
const imageFile = ref(null);   // anh moi chon
const imagePreview = ref('');  // URL xem truoc
const removeImage = ref(false);
const saving = ref(false);
const formError = ref('');

function blank() {
  return { name: '', quantity: 1, filter_status: 'UNFILTERED', tracking_code: '', alt_code: '', alt_code2: '', order_code: '', partner_name: '', partner_note: '', image_path: null };
}
function openAdd() { editingId.value = null; Object.assign(form, blank()); resetImage(); formError.value = ''; showForm.value = true; }
function openEdit(r) {
  editingId.value = r.id; Object.assign(form, blank(), r); resetImage(); formError.value = ''; showForm.value = true;
}
function resetImage() { imageFile.value = null; imagePreview.value = ''; removeImage.value = false; }
function pickImage(e) {
  const f = e.target.files?.[0]; e.target.value = '';
  if (!f) return;
  if (!/^image\//.test(f.type)) { formError.value = 'Chỉ chọn file ảnh.'; return; }
  imageFile.value = f; removeImage.value = false;
  imagePreview.value = URL.createObjectURL(f);
}
function dropImage() { imageFile.value = null; imagePreview.value = ''; removeImage.value = true; }
const shownImage = computed(() => imagePreview.value || (removeImage.value ? '' : form.image_path || ''));

async function save() {
  formError.value = '';
  if (!form.name.trim()) return (formError.value = 'Vui lòng nhập tên hàng.');
  if (!form.tracking_code.trim()) return (formError.value = 'Vui lòng nhập mã tracking.');
  saving.value = true;
  try {
    const body = { ...form };
    const res = editingId.value ? await api.updateProduct(editingId.value, body) : await api.createProduct(body);
    const id = res.data.id;
    if (imageFile.value) await api.uploadProductImage(id, imageFile.value);
    else if (removeImage.value && editingId.value && form.image_path) await api.removeProductImage(id);
    showForm.value = false;
    await load(editingId.value ? pagination.value.page : pagination.value.total_pages);
  } catch (e) { formError.value = e.message; } finally { saving.value = false; }
}
async function remove() {
  if (!confirm('Xóa mặt hàng này?')) return;
  saving.value = true;
  try { await api.deleteProduct(editingId.value); showForm.value = false; await load(pagination.value.page); }
  catch (e) { formError.value = e.message; } finally { saving.value = false; }
}
</script>

<template>
  <div class="mx-auto max-w-[1400px] px-4 py-6 sm:px-6">
    <div class="mb-5 flex items-center justify-between gap-3">
      <h1 class="border-l-4 border-navy pl-3 text-2xl font-extrabold text-slate-900">Danh sách mặt hàng</h1>
      <button class="btn-accent" @click="openAdd"><Plus class="h-4 w-4" /> Thêm mặt hàng</button>
    </div>

    <div class="card overflow-hidden">
      <!-- Tim kiem -->
      <div class="flex flex-wrap items-center gap-2 border-b border-slate-200 bg-slate-50 p-4">
        <div class="relative">
          <select v-model="field" class="input h-10 w-40 cursor-pointer appearance-none pr-8">
            <option v-for="f in fields" :key="f.v" :value="f.v">{{ f.label }}</option>
          </select>
          <ChevronDown class="pointer-events-none absolute right-2.5 top-3 h-4 w-4 text-slate-400" />
        </div>
        <input v-model="keyword" :placeholder="placeholder" class="input h-10 min-w-[240px] flex-1" @keyup.enter="doSearch" />
        <button class="btn-outline h-10 px-3" title="Tìm kiếm" @click="doSearch"><Search class="h-4 w-4" /></button>
        <button class="btn-outline h-10" @click="clearSearch">Xóa tìm kiếm</button>
      </div>

      <!-- Tab loc -->
      <div class="flex gap-1 border-b border-slate-200 px-3">
        <button v-for="t in tabs" :key="t.v" @click="tab = t.v"
          class="flex items-center gap-2 border-b-2 px-4 py-3 text-sm font-medium transition"
          :class="tab === t.v ? 'border-navy bg-slate-100 text-slate-900' : 'border-transparent text-slate-600 hover:text-slate-900'">
          <span class="h-2 w-2 rounded-full" :class="t.dot"></span>{{ t.label }}
        </button>
      </div>

      <p v-if="error" class="px-4 py-3 text-sm text-red-600">{{ error }}</p>

      <!-- Bang -->
      <div class="overflow-x-auto">
        <table class="w-full min-w-[960px] text-sm">
          <thead>
            <tr class="border-b border-slate-200 bg-slate-50 text-left text-xs font-bold uppercase tracking-wide text-slate-700">
              <th class="w-16 px-4 py-3 text-center">STT</th>
              <th class="w-28 px-3 py-3 text-center">Ảnh</th>
              <th class="px-3 py-3">Tên hàng</th>
              <th class="w-80 px-3 py-3">Tracking</th>
              <th class="w-64 px-3 py-3">Mã đơn hàng</th>
              <th class="w-48 px-3 py-3">Đối tác</th>
              <th class="w-16 px-3 py-3"></th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="(r, i) in rows" :key="r.id" class="border-b border-slate-100 align-middle hover:bg-slate-50/70">
              <td class="px-4 py-3 text-center text-slate-700">{{ stt(i) }}</td>
              <td class="px-3 py-3">
                <div class="mx-auto flex h-[60px] w-[60px] items-center justify-center overflow-hidden rounded border border-slate-200 bg-slate-50">
                  <img v-if="r.image_path" :src="r.image_path" class="h-full w-full object-contain" alt="" />
                  <ImageIcon v-else class="h-6 w-6 text-slate-300" />
                </div>
              </td>
              <td class="px-3 py-3">
                <div class="font-medium text-slate-800">{{ r.name }}</div>
                <div class="mt-1.5 flex items-center justify-between gap-3">
                  <span class="rounded border px-2 py-0.5 text-xs"
                    :class="r.filter_status === 'FILTERED' ? 'border-emerald-200 bg-emerald-50 text-emerald-700' : 'border-red-200 bg-red-50 text-red-600'">
                    {{ r.filter_status === 'FILTERED' ? 'Dịch lọc' : 'Chưa dịch lọc' }}
                  </span>
                  <span class="rounded bg-slate-100 px-2 py-0.5 text-xs font-bold text-slate-700">SL: {{ r.quantity }}</span>
                </div>
              </td>
              <td class="px-3 py-3">
                <div class="flex items-center justify-between gap-2">
                  <span class="flex items-center gap-1.5 font-mono text-[15px] font-bold text-slate-900">
                    {{ r.tracking_code }}
                    <button class="text-slate-500 hover:text-navy" title="Sao chép" @click="copy(r.tracking_code)">
                      <Check v-if="copied === r.tracking_code" class="h-4 w-4 text-emerald-600" /><Copy v-else class="h-4 w-4" />
                    </button>
                  </span>
                  <button class="text-slate-500 hover:text-navy" title="Tìm theo mã này" @click="searchBy('tracking', r.tracking_code)"><Search class="h-4 w-4" /></button>
                </div>
                <div v-if="r.alt_code || r.alt_code2" class="mt-1 text-xs text-slate-500">Mã tracking khác: {{ [r.alt_code, r.alt_code2].filter(Boolean).join(', ') }}</div>
              </td>
              <td class="px-3 py-3">
                <div v-if="r.order_code" class="flex items-center justify-between gap-2">
                  <span class="flex items-center gap-1.5 font-mono text-[15px] font-bold text-slate-900">
                    {{ r.order_code }}
                    <button class="text-slate-500 hover:text-navy" title="Sao chép" @click="copy(r.order_code)">
                      <Check v-if="copied === r.order_code" class="h-4 w-4 text-emerald-600" /><Copy v-else class="h-4 w-4" />
                    </button>
                  </span>
                  <button class="text-slate-500 hover:text-navy" title="Tìm theo mã này" @click="searchBy('order', r.order_code)"><Search class="h-4 w-4" /></button>
                </div>
              </td>
              <td class="px-3 py-3">
                <div class="font-semibold text-slate-800">{{ r.partner_name }}</div>
                <div class="text-slate-400">{{ r.partner_note }}</div>
              </td>
              <td class="px-3 py-3 text-center">
                <button class="text-navy hover:text-accent" title="Xem / sửa" @click="openEdit(r)"><Eye class="h-5 w-5" /></button>
              </td>
            </tr>
            <tr v-if="!rows.length && !loading">
              <td colspan="7" class="px-4 py-14 text-center text-slate-400">Chưa có mặt hàng nào. Bấm “Thêm mặt hàng” để nhập.</td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- Phan trang -->
      <div class="flex flex-wrap items-center justify-end gap-3 px-4 py-3 text-sm text-slate-700">
        <span>Tổng {{ pagination.total }} dòng hàng</span>
        <button class="rounded p-1 disabled:opacity-30" :disabled="pagination.page <= 1" @click="load(pagination.page - 1)"><ChevronLeft class="h-4 w-4" /></button>
        <span class="flex h-8 min-w-8 items-center justify-center rounded border border-navy px-2 font-semibold">{{ pagination.page }}</span>
        <button class="rounded p-1 disabled:opacity-30" :disabled="pagination.page >= pagination.total_pages" @click="load(pagination.page + 1)"><ChevronRight class="h-4 w-4" /></button>
        <select v-model.number="pagination.limit" class="h-8 cursor-pointer rounded border border-slate-300 bg-white px-2 text-sm">
          <option v-for="l in limits" :key="l" :value="l">{{ l }} / trang</option>
        </select>
      </div>
    </div>

    <!-- Form them / sua -->
    <div v-if="showForm" class="fixed inset-0 z-40 flex items-start justify-center overflow-y-auto bg-black/50 p-4" @mousedown.self="showForm = false">
      <form class="card my-8 w-full max-w-2xl p-6" @submit.prevent="save">
        <div class="mb-4 flex items-center justify-between">
          <h2 class="text-lg font-bold text-slate-900">{{ editingId ? 'Sửa mặt hàng' : 'Thêm mặt hàng' }}</h2>
          <button type="button" class="text-slate-400 hover:text-slate-700" @click="showForm = false"><X class="h-5 w-5" /></button>
        </div>

        <div class="grid gap-4 sm:grid-cols-2">
          <label class="sm:col-span-2 block text-sm font-medium text-slate-700">Tên hàng *
            <input v-model="form.name" class="input mt-1" maxlength="300" />
          </label>
          <label class="block text-sm font-medium text-slate-700">Số lượng (SL)
            <input v-model.number="form.quantity" type="number" min="1" class="input mt-1" />
          </label>
          <label class="block text-sm font-medium text-slate-700">Trạng thái
            <select v-model="form.filter_status" class="input mt-1">
              <option value="UNFILTERED">Chưa dịch lọc</option>
              <option value="FILTERED">Dịch lọc</option>
            </select>
          </label>
          <label class="block text-sm font-medium text-slate-700">Tracking *
            <input v-model="form.tracking_code" class="input mt-1 font-mono" maxlength="100" />
          </label>
          <label class="block text-sm font-medium text-slate-700">Mã tracking khác (1)
            <input v-model="form.alt_code" class="input mt-1 font-mono" maxlength="100" />
          </label>
          <label class="block text-sm font-medium text-slate-700">Mã tracking khác (2)
            <input v-model="form.alt_code2" class="input mt-1 font-mono" maxlength="100" />
          </label>
          <label class="block text-sm font-medium text-slate-700">Mã đơn hàng
            <input v-model="form.order_code" class="input mt-1 font-mono" maxlength="100" />
          </label>
          <label class="block text-sm font-medium text-slate-700">Đối tác
            <input v-model="form.partner_name" class="input mt-1" maxlength="100" />
          </label>
          <label class="block text-sm font-medium text-slate-700">Ghi chú đối tác
            <input v-model="form.partner_note" class="input mt-1" maxlength="200" />
          </label>

          <div class="sm:col-span-2">
            <div class="mb-1 text-sm font-medium text-slate-700">Ảnh</div>
            <div class="flex items-center gap-3">
              <div class="flex h-[72px] w-[72px] items-center justify-center overflow-hidden rounded border border-slate-200 bg-slate-50">
                <img v-if="shownImage" :src="shownImage" class="h-full w-full object-contain" alt="" />
                <ImageIcon v-else class="h-7 w-7 text-slate-300" />
              </div>
              <label class="btn-outline cursor-pointer"><ImagePlus class="h-4 w-4" /> Chọn ảnh
                <input type="file" accept="image/*" class="hidden" @change="pickImage" />
              </label>
              <button v-if="shownImage" type="button" class="text-sm text-red-600 hover:underline" @click="dropImage">Bỏ ảnh</button>
            </div>
          </div>
        </div>

        <p v-if="formError" class="mt-4 rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700">{{ formError }}</p>

        <div class="mt-6 flex items-center justify-between">
          <button v-if="editingId" type="button" class="btn-outline !border-red-200 !text-red-600 hover:!bg-red-50" :disabled="saving" @click="remove">
            <Trash2 class="h-4 w-4" /> Xóa
          </button>
          <span v-else></span>
          <div class="flex gap-2">
            <button type="button" class="btn-outline" @click="showForm = false">Hủy</button>
            <button type="submit" class="btn-accent" :disabled="saving">{{ saving ? 'Đang lưu…' : 'Lưu' }}</button>
          </div>
        </div>
      </form>
    </div>
  </div>
</template>

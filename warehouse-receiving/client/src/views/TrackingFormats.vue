<script setup>
import { ref, reactive, onMounted } from 'vue';
import { ArrowLeft, Plus, X, Pencil, Trash2, FlaskConical } from 'lucide-vue-next';
import { api } from '../api';

const MODES = [
  { v: 'FULL', label: 'Giữ nguyên', hint: 'Dùng chính mã vạch' },
  { v: 'LAST', label: 'Lấy N ký tự cuối', hint: 'Số ký tự cần lấy, vd 12' },
  { v: 'DROP_FIRST', label: 'Bỏ N ký tự đầu', hint: 'Số ký tự cần bỏ, vd 8' },
  { v: 'REGEX', label: 'Lấy phần khớp regex', hint: 'Regex, vd 1Z[0-9A-Z]{16}' },
];
const CARRIERS = ['USPS', 'UPS', 'FEDEX', 'DHL', 'AMAZON'];
const modeLabel = (v) => MODES.find((m) => m.v === v)?.label;

const rows = ref([]);
const error = ref('');
async function load() { try { rows.value = (await api.listFormats()).data; } catch (e) { error.value = e.message; } }
onMounted(load);

// ---------- Thu ma ----------
const test = reactive({ barcode: '', carrier_name: '' });
const result = ref(null);
const testError = ref('');
async function runTest() {
  testError.value = ''; result.value = null;
  try { result.value = (await api.testFormat({ ...test })).data; } catch (e) { testError.value = e.message; }
}
const methodText = { EXACT: 'Khớp nguyên mã', DERIVED: 'Khớp mã rút ra theo định dạng hãng', CONTAINS: 'Khớp dự phòng (mã trong danh sách nằm trong mã vạch)' };

// ---------- Them / sua ----------
const showForm = ref(false);
const editingId = ref(null);
const form = reactive({});
const formError = ref('');
const blank = () => ({ carrier: 'FEDEX', name: '', detect_regex: '', extract_mode: 'FULL', extract_param: '', is_active: true, sort_order: 100 });
function openAdd() { editingId.value = null; Object.assign(form, blank()); formError.value = ''; showForm.value = true; }
function openEdit(r) { editingId.value = r.id; Object.assign(form, blank(), r, { extract_param: r.extract_param || '' }); formError.value = ''; showForm.value = true; }
async function save() {
  formError.value = '';
  try {
    if (editingId.value) await api.updateFormat(editingId.value, { ...form }); else await api.createFormat({ ...form });
    showForm.value = false; await load();
  } catch (e) { formError.value = e.message; }
}
async function toggle(r) { try { await api.updateFormat(r.id, { ...r, is_active: !r.is_active }); await load(); } catch (e) { error.value = e.message; } }
async function remove(r) {
  if (!confirm(`Xóa định dạng “${r.name}”?`)) return;
  try { await api.deleteFormat(r.id); await load(); } catch (e) { error.value = e.message; }
}
</script>

<template>
  <div>
    <RouterLink to="/receiving/sessions" class="btn-outline mb-4 !border-navy !text-navy"><span class="flex h-5 w-5 items-center justify-center rounded bg-navy text-white"><ArrowLeft class="h-3.5 w-3.5" /></span> Quay lại · Phiên nhận hàng</RouterLink>
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div>
        <h1 class="border-l-4 border-navy pl-3 text-2xl font-extrabold text-slate-900">Định dạng mã tracking</h1>
        <p class="mt-1 mb-4 max-w-3xl text-sm text-slate-500">Mỗi hãng vận chuyển in mã vạch khác nhau (vd FedEx 34 số, USPS có tiền tố 420 + ZIP). Từ mã vạch quét được, hệ thống rút ra mã tracking thật theo các định dạng bên dưới rồi đối chiếu với Danh sách mặt hàng.</p>
      </div>
      <button class="btn-accent mt-2" @click="openAdd"><Plus class="h-4 w-4" /> Thêm định dạng</button>
    </div>

    <!-- Thu ma -->
    <div class="card mb-4 p-4">
      <h2 class="mb-2 flex items-center gap-2 text-base font-bold text-slate-900"><FlaskConical class="h-4 w-4 text-accent" /> Thử mã vạch</h2>
      <div class="flex flex-wrap gap-2">
        <input v-model="test.barcode" class="input h-10 min-w-[320px] flex-1 font-mono" placeholder="Dán mã vạch quét được (vd 1001892000000000000300470092728)" @keyup.enter="runTest" />
        <input v-model="test.carrier_name" class="input h-10 w-96" placeholder="Hãng của phiên (tuỳ chọn, chỉ để chọn hãng khi mã khớp nhiều hãng)" @keyup.enter="runTest" />
        <button class="btn-navy h-10" @click="runTest">Thử</button>
      </div>
      <p v-if="testError" class="mt-2 text-sm text-red-600">{{ testError }}</p>
      <div v-if="result" class="mt-3 rounded-lg border p-3 text-sm" :class="result.product ? 'border-emerald-200 bg-emerald-50' : 'border-red-200 bg-red-50'">
        <div class="font-bold" :class="result.product ? 'text-emerald-700' : 'text-red-600'">
          {{ result.product ? 'KHỚP — ' + methodText[result.method] : 'KHÔNG CÓ trong Danh sách mặt hàng (sẽ báo FAIL)' }}
        </div>
        <div v-if="result.product" class="mt-1">Mặt hàng: <b>{{ result.product.name }}</b> · Tracking: <span class="font-mono font-bold">{{ result.product.tracking_code }}</span></div>
        <div class="mt-1">Hãng của mã: <b>{{ result.carrier || 'không xác định' }}</b></div>
        <div class="mt-2 text-xs text-slate-600">Các mã đã thử:</div>
        <ul class="mt-1 space-y-0.5 text-xs">
          <li v-for="c in result.candidates" :key="c.value"><span class="font-mono font-semibold">{{ c.value }}</span> <span class="text-slate-500">{{ c.format ? '← ' + c.format : '(mã gốc)' }}</span></li>
        </ul>
      </div>
    </div>

    <p v-if="error" class="mb-2 text-sm text-red-600">{{ error }}</p>
    <div class="card overflow-x-auto">
      <table class="w-full min-w-[900px] text-sm">
        <thead><tr class="bg-navy text-left text-xs font-bold text-white">
          <th class="px-3 py-3">Hãng</th><th class="px-3 py-3">Định dạng</th><th class="px-3 py-3">Nhận biết (regex)</th><th class="px-3 py-3">Cách rút mã</th><th class="w-20 px-3 py-3 text-center">Bật</th><th class="w-20"></th>
        </tr></thead>
        <tbody>
          <tr v-for="r in rows" :key="r.id" class="border-b border-slate-100" :class="{ 'opacity-50': !r.is_active }">
            <td class="px-3 py-2.5"><span class="rounded bg-slate-100 px-2 py-0.5 text-xs font-bold">{{ r.carrier }}</span></td>
            <td class="px-3 py-2.5">{{ r.name }}</td>
            <td class="px-3 py-2.5 font-mono text-xs">{{ r.detect_regex }}</td>
            <td class="px-3 py-2.5">{{ modeLabel(r.extract_mode) }}<span v-if="r.extract_param" class="ml-1 font-mono text-xs text-slate-500">({{ r.extract_param }})</span></td>
            <td class="px-3 py-2.5 text-center"><input type="checkbox" :checked="r.is_active" @change="toggle(r)" /></td>
            <td class="px-3 py-2.5"><div class="flex justify-end gap-3">
              <button class="text-slate-700 hover:text-accent" title="Sửa" @click="openEdit(r)"><Pencil class="h-4 w-4" /></button>
              <button class="text-red-500 hover:text-red-700" title="Xóa" @click="remove(r)"><Trash2 class="h-4 w-4" /></button>
            </div></td>
          </tr>
          <tr v-if="!rows.length"><td colspan="6" class="py-10 text-center text-slate-400">Chưa có định dạng nào.</td></tr>
        </tbody>
      </table>
    </div>
    <p class="mt-3 text-xs text-slate-500">Quy ước: regex áp lên mã đã chuẩn hóa (bỏ khoảng trắng và ký tự ẩn, chữ HOA). Mã quét không khớp định dạng nào vẫn được thử nguyên mã, và thử dự phòng "mã trong danh sách (từ 10 ký tự) nằm trong mã vạch".</p>

    <div v-if="showForm" class="fixed inset-0 z-40 flex items-start justify-center overflow-y-auto bg-black/50 p-4" @mousedown.self="showForm = false">
      <form class="card my-8 w-full max-w-xl p-6" @submit.prevent="save">
        <div class="mb-4 flex items-center justify-between"><h2 class="text-lg font-bold">{{ editingId ? 'Sửa định dạng' : 'Thêm định dạng' }}</h2>
          <button type="button" class="text-slate-400 hover:text-slate-700" @click="showForm = false"><X class="h-5 w-5" /></button></div>
        <div class="grid gap-3 sm:grid-cols-2">
          <label class="block text-sm font-medium text-slate-700">Hãng
            <input v-model="form.carrier" list="carriers" class="input mt-1 uppercase" maxlength="30" /><datalist id="carriers"><option v-for="c in CARRIERS" :key="c" :value="c" /></datalist></label>
          <label class="block text-sm font-medium text-slate-700">Thứ tự ưu tiên<input v-model.number="form.sort_order" type="number" class="input mt-1" /></label>
          <label class="block text-sm font-medium text-slate-700 sm:col-span-2">Tên định dạng *<input v-model="form.name" class="input mt-1" maxlength="100" /></label>
          <label class="block text-sm font-medium text-slate-700 sm:col-span-2">Nhận biết (regex) *<input v-model="form.detect_regex" class="input mt-1 font-mono" maxlength="200" placeholder="^\d{34}$" /></label>
          <label class="block text-sm font-medium text-slate-700">Cách rút mã
            <select v-model="form.extract_mode" class="input mt-1"><option v-for="m in MODES" :key="m.v" :value="m.v">{{ m.label }}</option></select></label>
          <label v-if="form.extract_mode !== 'FULL'" class="block text-sm font-medium text-slate-700">Tham số
            <input v-model="form.extract_param" class="input mt-1 font-mono" :placeholder="MODES.find((m) => m.v === form.extract_mode).hint" /></label>
          <label class="flex items-center gap-2 text-sm sm:col-span-2"><input v-model="form.is_active" type="checkbox" /> Đang bật</label>
        </div>
        <p v-if="formError" class="mt-3 text-sm text-red-600">{{ formError }}</p>
        <div class="mt-5 flex justify-end gap-2"><button type="button" class="btn-outline" @click="showForm = false">Hủy</button><button class="btn-accent">Lưu</button></div>
      </form>
    </div>
  </div>
</template>

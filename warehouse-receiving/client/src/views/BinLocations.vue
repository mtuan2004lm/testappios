<script setup>
import { ref, reactive, computed, onMounted, watch } from 'vue';
import { ArrowLeft, Search, Plus, LayoutGrid, Pencil, Trash2, X } from 'lucide-vue-next';
import { api } from '../api';

const PARTS = [
  { k: 'zone', label: 'Khu' }, { k: 'subzone', label: 'Tiểu khu' }, { k: 'aisle', label: 'Lối' },
  { k: 'rack', label: 'Giá' }, { k: 'level', label: 'Tầng' }, { k: 'cell', label: 'Ô' },
];
const rows = ref([]);
const total = ref(0);
const search = ref('');
const error = ref('');
async function load() {
  error.value = '';
  try { const r = await api.listBins({ search: search.value.trim() }); rows.value = r.data; total.value = r.total; }
  catch (e) { error.value = e.message; }
}
let t; watch(search, () => { clearTimeout(t); t = setTimeout(load, 250); });
onMounted(load);

const detail = (r) => PARTS.filter((p) => r[p.k]).map((p) => `${p.label} ${r[p.k]}`).join(' · ');
const fmt = (v) => { const d = new Date(v), p = (n) => String(n).padStart(2, '0'); return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`; };

// ---------- Form them ----------
const mode = ref('one'); // one | many
const blank = () => ({ zone: '', subzone: '', aisle: '', rack: '', level: '', cell: '', alias: '' });
const form = reactive(blank());
const msg = ref(''); const formError = ref(''); const saving = ref(false);
const previewCode = computed(() => PARTS.map((p) => form[p.k].trim()).filter(Boolean).join('-'));

// Mo rong "01-05" -> 01,02,...,05 ; "A-C" -> A,B,C ; "1,3,5" ; chuoi thuong giu nguyen
function expand(text) {
  const out = [];
  for (const tok of String(text || '').split(',').map((s) => s.trim()).filter(Boolean)) {
    let m = tok.match(/^(\d+)\s*-\s*(\d+)$/);
    if (m) {
      const [a, b] = [Number(m[1]), Number(m[2])], w = m[1].length > 1 && m[1].startsWith('0') ? m[1].length : 0;
      if (b < a || b - a > 500) { out.push(tok); continue; }
      for (let i = a; i <= b; i++) out.push(w ? String(i).padStart(w, '0') : String(i));
      continue;
    }
    m = tok.match(/^([A-Za-z])\s*-\s*([A-Za-z])$/);
    if (m && m[2].toUpperCase() >= m[1].toUpperCase()) {
      for (let c = m[1].toUpperCase().charCodeAt(0); c <= m[2].toUpperCase().charCodeAt(0); c++) out.push(String.fromCharCode(c));
      continue;
    }
    out.push(tok);
  }
  return out;
}
const combos = computed(() => {
  const lists = PARTS.map((p) => expand(form[p.k]));
  if (lists.every((l) => !l.length)) return [];
  let acc = [{}];
  PARTS.forEach((p, i) => {
    const l = lists[i].length ? lists[i] : [''];
    acc = acc.flatMap((o) => l.map((v) => ({ ...o, [p.k]: v })));
  });
  return acc.slice(0, 1001);
});
const comboCode = (o) => PARTS.map((p) => o[p.k]).filter(Boolean).join('-');

async function add() {
  formError.value = ''; msg.value = ''; saving.value = true;
  try {
    if (mode.value === 'one') {
      await api.createBin({ ...form }); msg.value = `Đã thêm vị trí ${previewCode.value}`;
    } else {
      if (!combos.value.length) throw new Error('Điền ít nhất một ô');
      if (combos.value.length > 1000) throw new Error('Tối đa 1000 vị trí mỗi lần');
      const r = await api.bulkBins(combos.value.map((o) => ({ ...o, alias: '' })));
      msg.value = `Đã thêm ${r.data.created} vị trí${r.data.skipped ? `, bỏ qua ${r.data.skipped} mã đã tồn tại` : ''}`;
    }
    Object.assign(form, blank()); await load();
  } catch (e) { formError.value = e.message; } finally { saving.value = false; }
}

// ---------- Sua / xoa ----------
const editing = ref(null);
const eform = reactive(blank());
const eError = ref('');
function openEdit(r) { editing.value = r; Object.assign(eform, blank(), { ...r }); for (const k of Object.keys(eform)) eform[k] ??= ''; eError.value = ''; }
async function saveEdit() {
  try { await api.updateBin(editing.value.id, { ...eform }); editing.value = null; await load(); } catch (e) { eError.value = e.message; }
}
async function remove(r) {
  if (!confirm(`Xóa vị trí ${r.code}? Hàng đang giữ ở vị trí này sẽ thành “chưa có vị trí”.`)) return;
  try { await api.deleteBin(r.id); await load(); } catch (e) { error.value = e.message; }
}
</script>

<template>
  <div>
    <RouterLink to="/receiving/sessions" class="btn-outline mb-4 !border-navy !text-navy"><span class="flex h-5 w-5 items-center justify-center rounded bg-navy text-white"><ArrowLeft class="h-3.5 w-3.5" /></span> Quay lại · Phiên nhận hàng</RouterLink>
    <h1 class="border-l-4 border-navy pl-3 text-2xl font-extrabold text-slate-900">Vị trí kệ</h1>
    <p class="mt-1 mb-4 text-sm text-slate-500">Các vị trí kệ tại Hub Oregon, dùng để ghi chỗ đặt hàng đang giữ và hàng bị chặn.</p>

    <div class="grid items-start gap-4 lg:grid-cols-[1fr_620px]">
      <!-- Danh sach -->
      <div class="card p-4">
        <div class="mb-3 flex items-center justify-between gap-3">
          <div class="relative w-72"><Search class="absolute left-3 top-2.5 h-4 w-4 text-slate-400" /><input v-model="search" class="input pl-9" placeholder="Tìm mã vị trí hoặc tên gọi…" /></div>
          <span class="text-xs text-slate-500">Hiển thị {{ rows.length }}/{{ total }} vị trí</span>
        </div>
        <p v-if="error" class="mb-2 text-sm text-red-600">{{ error }}</p>
        <table class="w-full text-sm">
          <thead><tr class="bg-slate-100 text-left text-xs font-bold text-slate-700">
            <th class="px-2.5 py-2">Mã vị trí</th><th class="px-2.5 py-2">Tên gọi</th><th class="px-2.5 py-2">Chi tiết</th><th class="px-2.5 py-2">Ngày tạo</th><th class="w-20"></th>
          </tr></thead>
          <tbody>
            <tr v-for="r in rows" :key="r.id" class="border-b border-slate-100">
              <td class="px-2.5 py-2.5"><span class="whitespace-nowrap rounded bg-slate-100 px-2 py-1 font-mono text-xs font-bold text-slate-900">{{ r.code }}</span></td>
              <td class="px-2.5 py-2.5">{{ r.alias }}</td>
              <td class="px-2.5 py-2.5 text-xs text-slate-400">{{ detail(r) }}</td>
              <td class="whitespace-nowrap px-2.5 py-2.5 text-slate-700">{{ fmt(r.created_at) }}</td>
              <td class="px-2.5 py-2.5"><div class="flex justify-end gap-3">
                <button class="text-slate-700 hover:text-accent" title="Sửa" @click="openEdit(r)"><Pencil class="h-4 w-4" /></button>
                <button class="text-red-500 hover:text-red-700" title="Xóa" @click="remove(r)"><Trash2 class="h-4 w-4" /></button>
              </div></td>
            </tr>
            <tr v-if="!rows.length"><td colspan="5" class="py-12 text-center text-slate-400">Chưa có vị trí nào. Thêm vị trí ở khung bên phải.</td></tr>
          </tbody>
        </table>
      </div>

      <!-- Them -->
      <form class="card p-4" @submit.prevent="add">
        <div class="mb-3 grid grid-cols-2 gap-1 rounded-lg bg-slate-100 p-1 text-sm font-medium">
          <button type="button" class="flex items-center justify-center gap-2 rounded-md py-2" :class="mode === 'one' ? 'bg-white shadow-sm' : 'text-slate-600'" @click="mode = 'one'"><Plus class="h-4 w-4" /> Thêm vị trí</button>
          <button type="button" class="flex items-center justify-center gap-2 rounded-md py-2" :class="mode === 'many' ? 'bg-white shadow-sm' : 'text-slate-600'" @click="mode = 'many'"><LayoutGrid class="h-4 w-4" /> Thêm nhiều vị trí</button>
        </div>
        <div class="mb-3 rounded border border-dashed border-slate-300 px-3 py-2 text-xs text-slate-500">
          <template v-if="mode === 'one'">Mã vị trí do hệ thống tự sinh từ các cấp đã điền<template v-if="previewCode">: <b class="font-mono text-slate-900">{{ previewCode }}</b></template></template>
          <template v-else>Mỗi ô nhập được khoảng hoặc danh sách, ví dụ <b>01-05</b>, <b>A-C</b>, <b>1,3,5</b>. Hệ thống tạo mọi tổ hợp<template v-if="combos.length">: <b class="text-slate-900">{{ combos.length > 1000 ? '>1000' : combos.length }} vị trí</b> (vd {{ comboCode(combos[0]) }}<template v-if="combos.length > 1"> … {{ comboCode(combos[Math.min(combos.length, 1000) - 1]) }}</template>)</template>.</template>
        </div>
        <div class="grid grid-cols-3 gap-2">
          <label v-for="p in PARTS" :key="p.k" class="flex overflow-hidden rounded border border-slate-300 bg-white text-sm focus-within:border-accent">
            <span class="shrink-0 whitespace-nowrap bg-slate-100 px-2.5 py-2 text-slate-700">{{ p.label }}</span>
            <input v-model="form[p.k]" class="w-full min-w-0 px-2 outline-none" maxlength="40" />
          </label>
        </div>
        <label v-if="mode === 'one'" class="mt-2 flex overflow-hidden rounded border border-slate-300 bg-white text-sm focus-within:border-accent">
          <span class="shrink-0 whitespace-nowrap bg-slate-100 px-2.5 py-2 text-slate-700">Tên gọi</span><input v-model="form.alias" class="w-full px-2 outline-none" maxlength="100" />
        </label>
        <p class="mt-2 text-xs text-slate-500">Điền ít nhất một ô. Mã vị trí được ghép tự động từ những ô bạn điền: Khu A + Giá 01 + Tầng 1 sẽ thành A-01-1.</p>
        <p v-if="formError" class="mt-2 text-sm text-red-600">{{ formError }}</p>
        <p v-if="msg" class="mt-2 text-sm text-emerald-600">{{ msg }}</p>
        <div class="mt-3 flex justify-end"><button class="btn-accent" :disabled="saving">{{ saving ? 'Đang lưu…' : 'Thêm' }}</button></div>
      </form>
    </div>

    <!-- Sua -->
    <div v-if="editing" class="fixed inset-0 z-40 flex items-start justify-center overflow-y-auto bg-black/50 p-4" @mousedown.self="editing = null">
      <form class="card my-8 w-full max-w-lg p-6" @submit.prevent="saveEdit">
        <div class="mb-4 flex items-center justify-between"><h2 class="text-lg font-bold">Sửa vị trí <span class="font-mono">{{ editing.code }}</span></h2>
          <button type="button" class="text-slate-400 hover:text-slate-700" @click="editing = null"><X class="h-5 w-5" /></button></div>
        <div class="grid grid-cols-2 gap-3">
          <label v-for="p in PARTS" :key="p.k" class="block text-sm font-medium text-slate-700">{{ p.label }}<input v-model="eform[p.k]" class="input mt-1" maxlength="40" /></label>
          <label class="col-span-2 block text-sm font-medium text-slate-700">Tên gọi<input v-model="eform.alias" class="input mt-1" maxlength="100" /></label>
        </div>
        <p v-if="eError" class="mt-3 text-sm text-red-600">{{ eError }}</p>
        <div class="mt-5 flex justify-end gap-2"><button type="button" class="btn-outline" @click="editing = null">Hủy</button><button class="btn-accent">Lưu</button></div>
      </form>
    </div>
  </div>
</template>

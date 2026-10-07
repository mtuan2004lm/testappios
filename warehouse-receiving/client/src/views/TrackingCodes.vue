<script setup>
import { ref, reactive, watch, onMounted, nextTick } from 'vue';
import { Upload, Sparkles, Search, Trash2, ChevronLeft, ChevronRight, ScanBarcode, X, ClipboardPaste } from 'lucide-vue-next';
import JsBarcode from 'jsbarcode';
import { api, fmtDateTime } from '../api';

const codes = ref([]);
const pagination = ref({ page: 1, limit: 20, total: 0, total_pages: 1 });
const search = ref('');
const loading = ref(false);
const message = ref(null); // { type: 'ok'|'error', text }

async function load(page = 1) {
  loading.value = true;
  try {
    const params = { page, limit: pagination.value.limit };
    if (search.value.trim()) params.search = search.value.trim();
    const res = await api.listTracking(params);
    codes.value = res.data;
    pagination.value = res.pagination;
  } catch (e) {
    message.value = { type: 'error', text: e.message };
  } finally {
    loading.value = false;
  }
}
let timer;
watch(search, () => { clearTimeout(timer); timer = setTimeout(() => load(1), 300); }); // debounce
onMounted(() => load());

// ---- Phan tich van ban dan vao / noi dung CSV ----
// Moi dong: "ma_tracking" hoac "ma_tracking, ma_kho" (ngan cach bang , ; hoac tab). Bo dong tieu de.
function parseLines(text) {
  const items = [];
  text.split(/\r?\n/).forEach((line, idx) => {
    const cells = line.split(/[,;\t]/).map((c) => c.trim().replace(/^"|"$/g, ''));
    if (!cells[0]) return;
    if (idx === 0 && /^(barcode|tracking|m[ãa] ?tracking)$/i.test(cells[0])) return; // dong tieu de
    items.push({ barcode: cells[0], warehouse_code: cells[1] || '' });
  });
  return items;
}

const pasteText = ref('');
const showPaste = ref(false);
const busy = ref(false);

async function runImport(items) {
  if (!items.length) { message.value = { type: 'error', text: 'Không có mã nào để nhập.' }; return; }
  busy.value = true;
  try {
    // Chia lo 5000 ma (gioi han cua server)
    let inserted = 0, updated = 0;
    for (let i = 0; i < items.length; i += 5000) {
      const { data } = await api.importTracking(items.slice(i, i + 5000));
      inserted += data.inserted; updated += data.updated;
    }
    message.value = { type: 'ok', text: `Đã nhập: ${inserted} mã mới, ${updated} mã đã có (cập nhật).` };
    pasteText.value = ''; showPaste.value = false;
    await load(1);
  } catch (e) {
    message.value = { type: 'error', text: e.message };
  } finally {
    busy.value = false;
  }
}
const importPasted = () => runImport(parseLines(pasteText.value));
async function onFile(e) {
  const file = e.target.files[0];
  e.target.value = '';
  if (file) runImport(parseLines(await file.text()));
}
async function generate() {
  busy.value = true;
  try {
    const { data } = await api.generateTracking(20);
    message.value = { type: 'ok', text: `Đã tạo ${data.inserted} mã mẫu (mã TINA…, đủ 4 nhóm khách hàng).` };
    await load(1);
  } catch (e) { message.value = { type: 'error', text: e.message }; } finally { busy.value = false; }
}
async function remove(c) {
  if (!confirm(`Xoá mã ${c.barcode}?`)) return;
  try { await api.deleteTracking(c.id); await load(pagination.value.page); } catch (e) { message.value = { type: 'error', text: e.message }; }
}

// ---- Modal ma vach de quet thu tren man hinh ----
const showBars = ref(false);
const barRefs = ref([]);
async function openBars() {
  showBars.value = true;
  await nextTick();
  codes.value.forEach((c, i) => {
    const el = barRefs.value[i];
    if (el) JsBarcode(el, c.barcode, { format: 'CODE128', height: 50, width: 1.6, fontSize: 13, margin: 4 });
  });
}
</script>

<template>
  <div class="space-y-5">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div>
        <h1 class="text-2xl font-bold text-navy">Danh sách mặt hàng</h1>
        <p class="text-sm text-slate-500">Mã tracking dự kiến của toàn kho — quét mã có trong danh sách sẽ được nhận bình thường</p>
      </div>
      <div class="flex flex-wrap gap-2">
        <button class="btn-outline" :disabled="busy" @click="generate"><Sparkles class="h-4 w-4" /> Tạo 20 mã mẫu</button>
        <label class="btn-outline cursor-pointer"><Upload class="h-4 w-4" /> Import CSV/TXT
          <input type="file" accept=".csv,.txt,.tsv,text/plain,text/csv" class="hidden" @change="onFile" />
        </label>
        <button class="btn-navy" @click="showPaste = true"><ClipboardPaste class="h-4 w-4" /> Dán danh sách mã</button>
      </div>
    </div>

    <div v-if="message" class="flex items-center justify-between rounded-lg px-4 py-3 text-sm"
      :class="message.type === 'ok' ? 'bg-emerald-50 text-emerald-700' : 'bg-red-50 text-red-600'">
      {{ message.text }}
      <button @click="message = null"><X class="h-4 w-4" /></button>
    </div>

    <div class="card overflow-hidden">
      <div class="flex flex-wrap items-center gap-3 border-b border-slate-100 p-4">
        <div class="relative w-full max-w-sm">
          <Search class="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" />
          <input v-model="search" class="input !pl-9" placeholder="Tìm mã tracking hoặc mã kho…" />
        </div>
        <button class="btn-outline ml-auto" :disabled="!codes.length" @click="openBars"><ScanBarcode class="h-4 w-4" /> Hiện mã vạch (để quét thử)</button>
      </div>
      <div class="overflow-x-auto">
        <table class="w-full min-w-[640px] text-left text-sm">
          <thead class="bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
            <tr><th class="px-4 py-3">Mã tracking</th><th class="px-4 py-3">Mã kho</th><th class="px-4 py-3">Ngày nhập</th><th class="px-4 py-3 text-right"></th></tr>
          </thead>
          <tbody class="divide-y divide-slate-100">
            <tr v-if="loading"><td colspan="4" class="px-4 py-10 text-center text-slate-400">Đang tải…</td></tr>
            <tr v-else-if="!codes.length"><td colspan="4" class="px-4 py-14 text-center text-slate-400">Chưa có mã nào. Bấm “Tạo 20 mã mẫu” để thử, hoặc dán/import danh sách của bạn.</td></tr>
            <tr v-for="c in codes" v-else :key="c.id" class="hover:bg-slate-50">
              <td class="px-4 py-2.5 font-mono text-xs font-semibold">{{ c.barcode }}</td>
              <td class="px-4 py-2.5">{{ c.warehouse_code || '—' }}</td>
              <td class="px-4 py-2.5 text-xs text-slate-500">{{ fmtDateTime(c.created_at) }}</td>
              <td class="px-4 py-2.5 text-right"><button class="text-slate-400 hover:text-red-500" title="Xoá" @click="remove(c)"><Trash2 class="h-4 w-4" /></button></td>
            </tr>
          </tbody>
        </table>
      </div>
      <div class="flex items-center justify-between border-t border-slate-100 px-4 py-3 text-sm text-slate-500">
        <span>Tổng {{ pagination.total }} mã</span>
        <div class="flex items-center gap-2">
          <button class="btn-outline !px-2 !py-1.5" :disabled="pagination.page <= 1" @click="load(pagination.page - 1)"><ChevronLeft class="h-4 w-4" /></button>
          <span>Trang <b class="text-navy">{{ pagination.page }}</b> / {{ pagination.total_pages }}</span>
          <button class="btn-outline !px-2 !py-1.5" :disabled="pagination.page >= pagination.total_pages" @click="load(pagination.page + 1)"><ChevronRight class="h-4 w-4" /></button>
        </div>
      </div>
    </div>

    <!-- Modal dan danh sach -->
    <div v-if="showPaste" class="fixed inset-0 z-50 flex items-center justify-center bg-navy/60 p-4" @click.self="showPaste = false">
      <div class="card w-full max-w-xl space-y-3 p-6">
        <div class="flex items-center justify-between">
          <h2 class="text-lg font-bold text-navy">Dán danh sách mã tracking</h2>
          <button class="text-slate-400 hover:text-slate-600" @click="showPaste = false"><X class="h-5 w-5" /></button>
        </div>
        <p class="text-xs text-slate-500">Mỗi dòng một mã. Có thể thêm mã kho sau dấu phẩy hoặc Tab, ví dụ: <code class="rounded bg-slate-100 px-1">1Z999AA10123456784, SGVO_123</code>. Có thể dán thẳng từ Excel (2 cột).</p>
        <textarea v-model="pasteText" rows="10" class="input font-mono" placeholder="1Z999AA10123456784&#10;9400111899223197428490, FDVAT HUE 55"></textarea>
        <div class="flex justify-end gap-2">
          <button class="btn-outline" @click="showPaste = false">Huỷ</button>
          <button class="btn-navy" :disabled="busy || !pasteText.trim()" @click="importPasted">{{ busy ? 'Đang nhập…' : 'Nhập mã' }}</button>
        </div>
      </div>
    </div>

    <!-- Modal ma vach -->
    <div v-if="showBars" class="fixed inset-0 z-50 overflow-auto bg-navy/60 p-4" @click.self="showBars = false">
      <div class="card mx-auto max-w-4xl space-y-4 p-6">
        <div class="flex items-center justify-between">
          <div>
            <h2 class="text-lg font-bold text-navy">Mã vạch (CODE128) — trang hiện tại</h2>
            <p class="text-xs text-slate-500">Dùng máy quét hoặc app trên điện thoại quét thẳng từ màn hình này để thử.</p>
          </div>
          <button class="text-slate-400 hover:text-slate-600" @click="showBars = false"><X class="h-5 w-5" /></button>
        </div>
        <div class="grid gap-4 sm:grid-cols-2">
          <div v-for="(c, i) in codes" :key="c.id" class="rounded-lg border border-slate-200 p-3 text-center">
            <svg :ref="(el) => (barRefs[i] = el)" class="mx-auto max-w-full"></svg>
            <div class="mt-1 text-xs text-slate-500">{{ c.warehouse_code || 'chưa có mã kho' }}</div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

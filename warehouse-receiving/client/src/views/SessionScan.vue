<script setup>
import { tr, trMsg } from '../i18n';
import { ref, computed, onMounted, onBeforeUnmount, nextTick } from 'vue';
import { useRouter } from 'vue-router';
import { ArrowLeft, Volume2, VolumeX, Search, ScanBarcode, Lock, Flag, AlertTriangle, CheckCircle2, Repeat2, HelpCircle, Hammer, PauseCircle, ShieldBan, Camera, Pencil, Check, X, Tag, Volume1, ImagePlus, Trash2 } from 'lucide-vue-next';
import { api, ApiError, fmtTime } from '../api';
import CarrierLogo from '../components/CarrierLogo.vue';
import StatusBadge from '../components/StatusBadge.vue';

import { BrowserMultiFormatReader } from '@zxing/browser';

const props = defineProps({ id: { type: String, required: true } });
const router = useRouter();

const session = ref(null);
const items = ref([]);
const exceptionCounts = ref({ UNKNOWN: 0, DAMAGED: 0, HOLDING: 0, BLOCKED: 0, NO_NAME: 0, DUPLICATE: 0, FAIL: 0 });
const pendingTracks = ref([]);          // cac tracking chua co thong tin cua tem dang quet (toi da 3)
const endBlock = ref(false);            // pop-up bat buoc quet QR END CODE
const loadError = ref('');

const code = ref('');
const search = ref('');
const sound = ref(true);
const busy = ref(false);
const scanInput = ref(null);

// Ket qua luot quet gan nhat: { kind: 'ok'|'business'|'unknown'|'duplicate'|'error', item?, message }
const last = ref(null);

// Ket qua tu app iOS (SUCCESS / FAIL) lay tu phien, hien o khung READY ~8 giay roi tro ve READY
const appEvent = ref(null);
let seenAt = null, appTimer = null, localMark = false;
function applyAppEvent(sess) {
  const at = sess.last_scan_at;
  if (!sess.last_scan_status || !at) return;
  if (localMark) { seenAt = at; return; }                         // vua quet tren web: da hien o khung roi
  const fresh = Date.now() - new Date(at).getTime() < 8000;
  if (seenAt === null) { seenAt = at; if (!fresh) return; }       // lan tai dau: chi hien neu vua xay ra
  else if (at === seenAt) return;
  seenAt = at;
  last.value = null;                                              // nhuong khung cho ket qua tu app
  appEvent.value = { status: sess.last_scan_status, barcode: sess.last_scan_barcode, text: sess.last_scan_text,
                     seq: sess.last_scan_status === 'TRACK' ? sess.last_scan_exception : null,
                     group: sess.last_scan_group, business: items.value.find((i) => i.barcode === sess.last_scan_barcode)?.business_type || null, blockReason: (sess.last_scan_status === 'SUCCESS' || sess.last_scan_status === 'NO_NAME') ? sess.last_scan_block : null, unknown: sess.last_scan_exception === 'UNKNOWN', notFound: sess.last_scan_exception === 'NOT_FOUND' };
  clearTimeout(appTimer);
  appTimer = setTimeout(() => { appEvent.value = null; }, 8000);
  const st = appEvent.value.status;
  if (appEvent.value.blockReason) warn();
  else if (st === 'SUCCESS') yes(); else if (st === 'TRACK' || st === 'NO_NAME') ting(); else beep(220, 300);   // FAIL / MÃ TRÙNG: tiếng trầm
}

const BLOCK_LABELS = { get DAMAGED() { return tr('Rách / móp / ướt / bẹp / vỡ seal / rò rỉ') }, get RETURN() { return tr('Trả hàng') }, get STORED_PENDING() { return tr('Lưu kho – chờ xác nhận gửi') }, get QTY_VERIFY() { return tr('Kiểm tra số lượng sản phẩm') }, get PHOTO_VIDEO() { return tr('Chụp ảnh và quay video') }, get CUSTOMS_SPLIT() { return tr('Tách kiện để kiểm hải quan') }, get REPACK() { return tr('Đóng gói lại / gia cố') }, get PRODUCT_INSPECT() { return tr('Kiểm tra sản phẩm (model, màu, size…)') } };
const blockLabel = (c) => BLOCK_LABELS[c] || c;
const warn = () => { beep(260, 160); setTimeout(() => beep(260, 160), 220); };   // tieng canh bao BLOCK
const businessLabel = (t) => (t === 'KINH_DOANH' ? tr('Kinh doanh') : t === 'KHONG_KINH_DOANH' ? tr('Không kinh doanh') : '—');

const isOpen = computed(() => session.value?.status === 'OPEN');
const selected = ref([]);
const allSelected = computed(() => filtered.value.length > 0 && filtered.value.every((i) => selected.value.includes(i.id)));
function toggleAll() { selected.value = allSelected.value ? [] : filtered.value.map((i) => i.id); }
async function deleteSelected() {
  const ids = [...selected.value];
  if (!ids.length) return;
  if (!confirm(tr('Xoá {0} kiện đã chọn? Không thể hoàn tác.', ids.length))) return;
  try { await api.deleteItems(props.id, ids); selected.value = []; last.value = null; await load(); } catch (e) { alert(e.message); }
}
const missingLabel = computed(() => items.value.filter((i) => !(i.label_photos || []).length).length);
const filtered = computed(() => {
  const q = search.value.trim().toLowerCase();
  return q ? items.value.filter((i) => i.barcode.toLowerCase().includes(q) || (i.customer_group || '').toLowerCase().includes(q) || (i.detected_warehouse_code || '').toLowerCase().includes(q)) : items.value;
});

const exceptionRows = [
  { key: 'UNKNOWN', get label() { return tr('Không xác định') }, icon: HelpCircle, color: 'text-red-600' },
  { key: 'DAMAGED', get label() { return tr('Hư hỏng') }, icon: Hammer, color: 'text-red-500' },
  { key: 'HOLDING', get label() { return tr('Đang giữ hàng') }, icon: PauseCircle, color: 'text-amber-500' },
  { key: 'BLOCKED', get label() { return tr('Bị chặn') }, icon: ShieldBan, color: 'text-rose-600' },
  { key: 'NO_NAME', label: 'No Name', icon: Tag, color: 'text-fuchsia-600' },
  { key: 'FAIL', get label() { return tr('Quét thất bại (FAIL)') }, icon: AlertTriangle, color: 'text-red-500' },
  { key: 'DUPLICATE', get label() { return tr('Mã trùng') }, icon: Repeat2, color: 'text-violet-500' },
];

async function load() {
  try {
    const { data } = await api.getSession(props.id);
    items.value = data.items;
    session.value = data.session;
    applyAppEvent(data.session);
    exceptionCounts.value = data.exception_counts;
    pendingTracks.value = data.pending_tracks || [];
    if (pendingTracks.value.length >= 3) endBlock.value = true;      // du 3 tracking khong co thong tin: bat buoc quet END CODE
    else if (!pendingTracks.value.length) endBlock.value = false;
  } catch (e) {
    loadError.value = e.message;
  }
}

// Phat tieng bip bang WebAudio (khong can file am thanh)
function beep(freq, ms = 120) {
  if (!sound.value) return;
  if (navigator.userActivation && !navigator.userActivation.hasBeenActive) return;   // trinh duyet chan am thanh khi chua bam/go gi tren trang
  try {
    const ctx = new (window.AudioContext || window.webkitAudioContext)();
    const osc = ctx.createOscillator();
    osc.frequency.value = freq;
    osc.connect(ctx.destination);
    osc.start();
    setTimeout(() => { osc.stop(); ctx.close(); }, ms);
  } catch { /* trinh duyet chan audio: bo qua */ }
}
// "yes" = 2 tieng cao tang dan; "ting" = 1 tieng cao ngan
const yes = () => { beep(660, 110); setTimeout(() => beep(990, 160), 130); };
const ting = () => beep(1500, 90);
const focusInput = () => nextTick(() => scanInput.value?.focus({ preventScroll: true }));   // preventScroll: không cuộn trang về đầu khi lấy lại focus
// Ô quét tự lấy lại focus khi mất focus, trừ khi người dùng vừa bấm vào link/nút/ô nhập khác (nếu không, bấm link "Label" sẽ bị cuộn về đầu trang và không mở được ảnh)
const refocusUnlessInteractive = (e) => { if (e?.relatedTarget?.closest?.('a, button, select, input, textarea, label')) return; if (isOpen.value && !busy.value && !editingTotal.value && !camOpen.value) focusInput(); };

async function submitScan() {
  const barcode = code.value.trim();
  if (!barcode || busy.value || !isOpen.value) return;
  busy.value = true;
  try {
    // May quet thuong gui chinh ma kho -> dung barcode lam detected_text
    const { data } = await api.scan(props.id, { barcode, detected_text: barcode });
    if (data.status === 'TRACK') {
      // Tracking chua co thong tin: ghi lai (TING), cho ma tiep theo tren tem hoac END CODE
      pendingTracks.value = data.pending;
      last.value = { kind: 'track', seq: data.seq, barcode: data.barcode, message: data.need_end_code ? tr('Đã đủ 3 tracking — quét QR END CODE') : tr('Quét tracking tiếp theo trên tem ({0}/3) hoặc QR END CODE', data.seq) };
      if (data.need_end_code) endBlock.value = true;
      ting();
      return;
    }
    items.value.unshift(data.item);
    session.value.scanned_count = data.scanned_count;
    pendingTracks.value = [];
    endBlock.value = false;
    if (data.blocked) {
      last.value = { kind: 'blocked', item: data.item, reason: data.block_reason_label, count: data.blocks?.length || 1, noName: data.status === 'NO_NAME' };
      warn();
    } else if (data.status === 'NO_NAME') {
      last.value = { kind: 'noname', item: data.item, message: data.warning };
      ting();
    } else if (data.item.exception_status === 'UNKNOWN' || !data.item.customer_group) {
      if (data.item.exception_status === 'UNKNOWN') exceptionCounts.value.UNKNOWN++;
      last.value = { kind: 'unknown', item: data.item, message: data.warning };
      beep(300, 250);
    } else if (data.item.business_type === 'KINH_DOANH') {
      last.value = { kind: 'business', item: data.item, message: data.warning };
      beep(520, 300);
    } else {
      last.value = { kind: 'ok', item: data.item };
      yes();
    }
  } catch (e) {
    if (e instanceof ApiError && e.code === 'DUPLICATE_BARCODE') {
      exceptionCounts.value.DUPLICATE = e.data.duplicate_count;
      last.value = { kind: 'duplicate', barcode, message: e.message };
      beep(200, 400);
    } else if (e instanceof ApiError && e.code === 'END_CODE_REQUIRED') {
      endBlock.value = true;
      last.value = { kind: 'error', title: 'END CODE', barcode, message: e.message };
      beep(200, 400);
    } else {
      last.value = { kind: 'error', title: e.code === 'TRACKING_NOT_FOUND' ? 'FAIL' : null, barcode,
                     message: e.code === 'TRACKING_NOT_FOUND' ? tr('Mã không có trong danh sách mặt hàng') : e.message };
      beep(200, 400);
      if (e.code === 'SESSION_CLOSED') load();
    }
  } finally {
    code.value = '';
    busy.value = false;
    localMark = true; await load(); localMark = false;   // dong bo bo dem; khong coi la ket qua tu app
    focusInput();
  }
}

const damagePhotos = (i) => (i.photo_urls || []).filter((u) => !(i.label_photos || []).includes(u));
async function uploadLabel(item, ev) {
  const file = ev.target.files?.[0];
  ev.target.value = '';
  if (!file) return;
  try { await api.uploadLabelPhoto(item.id, file); await load(); } catch (e) { alert(e.message); }
  focusInput();
}

async function toggleBusiness(item) {
  try {
    const { data } = await api.toggleBusiness(item.id);
    Object.assign(item, data);
    if (last.value?.item?.id === item.id) { last.value.item = item; last.value.kind = item.business_type === 'KINH_DOANH' ? 'business' : 'ok'; last.value.message = null; }
  } catch (e) { alert(e.message); }
}

async function changeException(item, status) {
  const prev = item.exception_status;
  try {
    const { data } = await api.setException(item.id, status);
    Object.assign(item, data);
    await load(); // dong bo lai bo dem ngoai le
  } catch (e) { item.exception_status = prev; alert(e.message); }
}

async function finalize() {
  if (!confirm(tr('Chốt số kiện = {0}?', session.value.scanned_count))) return;
  try { session.value = (await api.finalize(props.id)).data; } catch (e) { alert(e.message); }
  focusInput();
}
async function closeSession() {
  if (!confirm(tr('Kết thúc phiên? Sau khi kết thúc sẽ không quét thêm được.'))) return;
  try { session.value = (await api.closeSession(props.id)).data; last.value = null; } catch (e) { alert(e.message); }
}

// ---- Nhap tay so kien cua phien ----
const editingTotal = ref(false);
const totalDraft = ref(0);
const totalInput = ref(null);
function startEditTotal() {
  if (!isOpen.value) return;
  totalDraft.value = session.value.total_expected_packages;
  editingTotal.value = true;
  nextTick(() => totalInput.value?.select());
}
async function saveTotal() {
  if (!editingTotal.value) return;
  editingTotal.value = false;
  const n = Number(totalDraft.value);
  if (!Number.isInteger(n) || n < 0 || n === session.value.total_expected_packages) { focusInput(); return; }
  try { session.value = (await api.updateExpected(props.id, n)).data; } catch (e) { alert(e.message); }
  focusInput();
}

// ---- Quet barcode giay bang camera (ZXing) ----
const camOpen = ref(false);
const camError = ref('');
const videoEl = ref(null);
let camControls = null;
let lastCamCode = '';
let lastCamAt = 0;

async function openCamera() {
  camError.value = '';
  camOpen.value = true;
  await nextTick();
  try {
    const reader = new BrowserMultiFormatReader();
    camControls = await reader.decodeFromVideoDevice(undefined, videoEl.value, (result) => {
      if (!result) return;
      const text = result.getText();
      const now = Date.now();
      if (text === lastCamCode && now - lastCamAt < 2500) return; // tranh doc lap lai cung mot ma khi van dang giu truoc camera
      lastCamCode = text; lastCamAt = now;
      code.value = text;
      submitScan();
    });
  } catch (e) {
    camError.value = e?.name === 'NotAllowedError' ? tr('Chưa được cấp quyền camera. Bấm biểu tượng khoá trên thanh địa chỉ để cho phép.') : tr('Không mở được camera: {0}', e?.message || e);
  }
}
function closeCamera() {
  camControls?.stop(); camControls = null;
  camOpen.value = false;
  focusInput();
}
// Tu dong cap nhat moi 2 giay de thay ngay cac kien do app iOS gui len (phien dang mo)
let poll = null;
onBeforeUnmount(() => { camControls?.stop(); clearInterval(poll); clearTimeout(appTimer); });

onMounted(async () => {
  await load();
  focusInput();
  poll = setInterval(() => { if (isOpen.value && !busy.value && !editingTotal.value) load(); }, 1000);
});
</script>

<template>
  <div v-if="loadError" class="card p-10 text-center text-red-500">{{ loadError }}</div>
  <div v-else-if="!session" class="card p-10 text-center text-slate-400">{{ tr('Đang tải…') }}</div>

  <div v-else class="space-y-5">
    <!-- Top bar -->
    <div class="card flex flex-wrap items-center gap-4 p-4">
      <button class="btn-outline" @click="router.push('/receiving/sessions')"><ArrowLeft class="h-4 w-4" /> {{ tr('Quay lại') }}</button>
      <div>
        <div class="flex items-center gap-2">
          <h1 class="text-xl font-bold text-navy">{{ tr('Phiên #{0}', String(session.id).padStart(4, '0')) }}</h1>
          <StatusBadge :status="session.status" />
        </div>
        <p class="text-sm text-slate-500">
          {{ tr('Xe {0} · Người giao: {1} · Cửa {2}', session.license_plate || '—', session.driver_name || '—', session.gate_code) }}
        </p>
      </div>
      <div class="ml-auto flex items-center gap-4">
        <div class="flex items-center gap-3"><CarrierLogo :name="session.carrier_name" size="lg" /><span class="hidden text-lg font-bold text-navy sm:block">{{ session.carrier_name }}</span></div>
        <button v-if="isOpen" class="btn-navy" @click="closeSession"><Flag class="h-4 w-4" /> {{ tr('Kết thúc phiên') }}</button>
      </div>
    </div>

    <div class="grid gap-5 lg:grid-cols-5">
      <!-- CỘT TRÁI: thao tác -->
      <div class="space-y-4 lg:col-span-2">
        <div class="card space-y-4 p-5">
          <label class="block text-sm font-semibold text-navy">{{ tr('Quét hoặc gõ mã rồi Enter') }}</label>
          <div class="relative">
            <ScanBarcode class="absolute left-3 top-1/2 h-6 w-6 -translate-y-1/2 text-slate-400" />
            <input ref="scanInput" v-model="code" :disabled="!isOpen || busy" autofocus autocomplete="off" spellcheck="false"
              :placeholder="tr('Quét hoặc gõ mã rồi Enter')" maxlength="100"
              class="w-full rounded-xl border-2 border-slate-300 py-4 pl-12 pr-14 font-mono text-lg outline-none focus:border-accent focus:ring-4 focus:ring-accent/20 disabled:bg-slate-100"
              @keydown.enter.prevent="submitScan" @blur="refocusUnlessInteractive($event)" />
            <button type="button" class="absolute right-3 top-1/2 -translate-y-1/2 text-slate-400 hover:text-accent" :title="sound ? tr('Tắt âm') : tr('Bật âm')" @click="sound = !sound; focusInput()">
              <Volume2 v-if="sound" class="h-6 w-6" /><VolumeX v-else class="h-6 w-6" />
            </button>
          </div>
          <div v-if="pendingTracks.length" class="rounded-xl border border-amber-300 bg-amber-50 px-3 py-2 text-sm text-amber-900">
            <div class="font-bold">{{ tr('Tem đang quét — {0}/3 tracking chưa có thông tin', pendingTracks.length) }}</div>
            <div v-for="t in pendingTracks" :key="t.seq" class="font-mono text-xs">{{ t.seq }}) {{ t.barcode }}</div>
            <div class="mt-1 text-xs">{{ pendingTracks.length >= 3 ? tr('Bắt buộc quét QR END CODE để kết thúc tem này.') : tr('Quét tracking tiếp theo trên tem; nếu tem hết mã thì quét QR END CODE.') }}</div>
          </div>
          <button v-if="isOpen" class="btn-outline w-full" @click="openCamera"><Camera class="h-4 w-4" /> {{ tr('Quét barcode giấy bằng camera') }}</button>
          <p v-if="!isOpen" class="rounded-lg bg-slate-100 px-3 py-2 text-sm text-slate-500">{{ tr('Phiên đã kết thúc — chỉ xem.') }}</p>

          <div class="relative">
            <Search class="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" />
            <input v-model="search" class="input !pl-9" :placeholder="tr('Tìm tracking trong phiên…')" />
          </div>

          <button class="btn-accent w-full !py-3" :disabled="!isOpen || !session.scanned_count" @click="finalize"><Lock class="h-4 w-4" /> {{ tr('Chốt kiện - END CODE') }}</button>
        </div>

        <div class="card p-5">
          <h2 class="mb-3 text-sm font-bold uppercase tracking-wide text-slate-500">{{ tr('Ngoại lệ') }}</h2>
          <ul class="divide-y divide-slate-100">
            <li v-for="r in exceptionRows" :key="r.key" class="flex items-center justify-between py-2.5 text-sm">
              <span class="flex items-center gap-2.5"><component :is="r.icon" class="h-4 w-4" :class="r.color" /><span :class="r.key === 'UNKNOWN' ? 'font-bold text-red-600' : ''">{{ r.label }}</span></span>
              <span class="min-w-8 rounded-full px-2.5 py-0.5 text-center text-xs font-bold" :class="exceptionCounts[r.key] ? 'bg-accent text-white' : 'bg-slate-100 text-slate-400'">{{ exceptionCounts[r.key] }}</span>
            </li>
          </ul>
        </div>
      </div>

      <!-- CỘT PHẢI: kết quả real-time -->
      <div class="space-y-4 lg:col-span-3">
        <div class="card flex flex-col items-center gap-4 bg-navy p-6 text-white sm:flex-row sm:justify-between">
          <div>
            <div class="text-xs font-semibold uppercase tracking-widest text-slate-400">{{ tr('Đã quét') }}</div>
            <div class="flex items-baseline font-mono text-6xl font-black leading-none">
              {{ session.scanned_count }}<span class="px-2 text-slate-500">/</span>
              <input v-if="editingTotal" ref="totalInput" v-model.number="totalDraft" type="number" min="0"
                class="w-32 rounded-lg border-2 border-accent bg-navy-700 px-2 text-6xl font-black text-white outline-none"
                @keydown.enter.prevent="saveTotal" @keydown.esc="editingTotal = false; focusInput()" @blur="saveTotal" />
              <button v-else class="group flex items-baseline text-slate-400 transition" :class="isOpen ? 'cursor-pointer hover:text-white' : 'cursor-default'"
                :title="isOpen ? tr('Bấm để nhập số kiện') : ''" @click="startEditTotal">
                {{ session.total_expected_packages }}
                <Pencil v-if="isOpen" class="ml-2 h-5 w-5 self-center text-slate-500 group-hover:text-accent" />
              </button>
            </div>
            <div class="mt-1 text-sm text-slate-400">{{ tr('kiện') }} <span v-if="isOpen" class="text-slate-500">{{ tr('· bấm số bên phải để nhập tay số kiện') }}</span></div>
          </div>
          <!-- Man hinh trang thai -->
          <div class="w-full flex-1 rounded-xl p-4 text-center sm:max-w-sm"
            :class="{
              'bg-white/10': !last && !appEvent, 'bg-emerald-500': last?.kind === 'ok' || (!last && !appEvent?.blockReason && appEvent?.status === 'SUCCESS'),
              'bg-accent': last?.kind === 'business',
              'bg-slate-500': last?.kind === 'unknown',
              'bg-amber-500': last?.kind === 'track' || (!last && appEvent?.status === 'TRACK'),
              'bg-fuchsia-600': last?.kind === 'noname' || (!last && !appEvent?.blockReason && appEvent?.status === 'NO_NAME'),
              'bg-red-700': last?.kind === 'blocked' || (!last && !!appEvent?.blockReason),
              'bg-red-600': last?.kind === 'duplicate' || last?.kind === 'error' || (!last && !appEvent?.blockReason && (appEvent?.status === 'FAIL' || appEvent?.status === 'DUPLICATE')) }">
            <template v-if="last?.kind === 'blocked' || (!last && appEvent?.blockReason)">
              <ShieldBan class="mx-auto h-7 w-7" />
              <div class="text-3xl font-extrabold tracking-widest">BLOCK</div>
              <div class="break-all font-mono text-lg font-bold">{{ last ? last.item.barcode : appEvent.barcode }}</div>
              <div class="text-sm font-bold">{{ last ? last.reason : blockLabel(appEvent.blockReason) }}</div>
              <div class="text-xs opacity-90">{{ tr('Khách yêu cầu block — kiện vẫn được ghi nhận') }}{{ last?.count > 1 ? tr(' (+{0} block khác)', last.count - 1) : '' }}<template v-if="last?.noName || appEvent?.status === 'NO_NAME'"> · NO NAME</template></div>
            </template>
            <template v-else-if="!last && appEvent && (appEvent.status === 'TRACK' || appEvent.status === 'NO_NAME')">
              <Tag class="mx-auto h-7 w-7" />
              <div class="text-3xl font-extrabold tracking-widest">{{ appEvent.status === 'TRACK' ? 'TING' : 'NO NAME' }}</div>
              <div class="break-all font-mono text-lg font-bold">{{ appEvent.barcode }}</div>
              <div class="text-sm font-semibold">{{ appEvent.status === 'TRACK' ? tr('Tracking {0}/3 chưa có thông tin', appEvent.seq || '') : tr('Cả 3 tracking không có thông tin') }}</div>
            </template>
            <template v-else-if="!last && appEvent">
              <component :is="appEvent.status === 'SUCCESS' ? CheckCircle2 : appEvent.status === 'DUPLICATE' ? Repeat2 : AlertTriangle" class="mx-auto h-7 w-7" />
              <div class="text-3xl font-extrabold tracking-widest">{{ appEvent.status === 'SUCCESS' ? 'SUCCESS' : appEvent.status === 'DUPLICATE' ? tr('MÃ TRÙNG') : 'FAIL' }}</div>
              <div v-if="appEvent.status === 'DUPLICATE'">
                <div class="break-all font-mono text-lg font-bold">{{ appEvent.barcode }}</div>
                <div class="text-sm font-semibold">{{ tr('Mã đã quét trong phiên này') }}</div>
              </div>
              <div v-else-if="appEvent.status === 'SUCCESS'" class="break-all font-mono text-lg font-bold">{{ appEvent.barcode }}</div>
              <div v-if="appEvent.status === 'SUCCESS'" class="mt-1 space-y-0.5 text-left text-sm font-semibold sm:mx-auto sm:w-fit">
                <div><span class="opacity-80">{{ tr('Nhóm KH:') }}</span> {{ appEvent.group || '—' }}</div>
                <div><span class="opacity-80">{{ tr('Mã kho:') }}</span> <span class="font-mono">{{ appEvent.text || '—' }}</span></div>
                <div><span class="opacity-80">{{ tr('Loại hình:') }}</span> {{ businessLabel(appEvent.business) }}</div>
              </div>
              <template v-else>
                <div v-if="appEvent.barcode" class="break-all font-mono text-lg font-bold">{{ appEvent.barcode }}</div>
                <div class="text-sm font-semibold">{{ appEvent.notFound ? tr('Mã không có trong danh sách mặt hàng') : tr('Không đọc được mã vạch') }}</div>
              </template>
              <div v-if="appEvent.status === 'FAIL'" class="text-sm font-semibold">{{ appEvent.group }}<span v-if="appEvent.text" class="ml-1 font-mono opacity-90">· {{ appEvent.text }}</span></div>
              <div v-if="appEvent.unknown" class="text-xs opacity-90">{{ tr('Mã không có trong danh sách mặt hàng (không xác định)') }}</div>
            </template>
            <template v-else-if="!last">
              <div class="text-2xl font-extrabold tracking-widest">READY</div>
              <div class="text-sm text-slate-300">{{ isOpen ? tr('Quét mã đầu tiên') : tr('Phiên đã đóng') }}</div>
            </template>
            <template v-else-if="last.kind === 'track'">
              <Tag class="mx-auto h-7 w-7" />
              <div class="text-3xl font-extrabold tracking-widest">TING</div>
              <div class="break-all font-mono text-lg font-bold">{{ last.barcode }}</div>
              <div class="text-sm font-semibold">{{ tr('Tracking {0}/3 chưa có thông tin', last.seq) }}</div>
              <div class="text-xs opacity-90">{{ trMsg(last.message) }}</div>
            </template>
            <template v-else-if="last.kind === 'noname'">
              <Tag class="mx-auto h-7 w-7" />
              <div class="text-3xl font-extrabold tracking-widest">NO NAME</div>
              <div class="break-all font-mono text-lg font-bold">{{ last.item.barcode }}</div>
              <div class="text-xs opacity-90">{{ trMsg(last.message) }}</div>
            </template>
            <template v-else-if="last.kind === 'duplicate' || last.kind === 'error'">
              <component :is="last.kind === 'duplicate' ? Repeat2 : AlertTriangle" class="mx-auto h-7 w-7" />
              <div class="text-xl font-extrabold">{{ last.kind === 'blocked' ? `BLOCK – ${last.reason}` : last.kind === 'duplicate' ? tr('MÃ TRÙNG') : (last.title || tr('LỖI')) }}</div>
              <div class="break-all font-mono text-lg font-bold">{{ last.barcode }}</div>
              <div class="text-xs opacity-90">{{ trMsg(last.message) }}</div>
            </template>
            <template v-else>
              <component :is="last.kind === 'ok' ? CheckCircle2 : AlertTriangle" class="mx-auto h-7 w-7" />
              <div class="text-xl font-extrabold">{{ last.item.customer_group || tr('KHÔNG XÁC ĐỊNH') }}</div>
              <div class="break-all font-mono text-lg font-bold">{{ last.item.barcode }}</div>
              <div class="mt-1 space-y-0.5 text-left text-sm font-semibold sm:mx-auto sm:w-fit">
                <div><span class="opacity-80">{{ tr('Mã kho:') }}</span> <span class="font-mono">{{ last.item.detected_warehouse_code || '—' }}</span></div>
                <div><span class="opacity-80">{{ tr('Loại hình:') }}</span> {{ businessLabel(last.item.business_type) }}</div>
              </div>
              <div v-if="last.message" class="mt-1 text-xs font-semibold">{{ trMsg(last.message) }}</div>
              <button v-if="last.kind === 'business'" class="mt-2 rounded-lg bg-white px-3 py-1.5 text-xs font-bold text-accent-dark hover:bg-orange-50" @click="toggleBusiness(last.item)">
                {{ tr('Không đủ điều kiện nhập khẩu → KHÔNG KINH DOANH') }}
              </button>
            </template>
          </div>
        </div>

        <!-- Lich su quet -->
        <!-- Lich su quet -->
        <div class="card overflow-hidden">
          <div class="flex flex-wrap items-center gap-x-3 gap-y-1 border-b border-slate-100 px-5 py-3 text-sm font-bold uppercase tracking-wide text-slate-500">{{ tr('Lịch sử quét ({0})', filtered.length) }}<span v-if="missingLabel" class="rounded-full bg-red-100 px-2.5 py-0.5 text-xs font-bold normal-case tracking-normal text-red-700" :title="tr('Kiện chưa có ảnh label — bấm \'Ảnh label\' ở dòng đó để bổ sung')">{{ tr('⚠ {0} kiện thiếu ảnh label', missingLabel) }}</span>
            <button v-if="isOpen && selected.length" type="button" class="ml-auto inline-flex items-center gap-1 rounded-lg border border-red-300 bg-red-50 px-3 py-1 text-xs font-bold normal-case tracking-normal text-red-700 hover:bg-red-100" @click="deleteSelected"><Trash2 class="h-3.5 w-3.5" />{{ tr('Xoá đã chọn ({0})', selected.length) }}</button></div>
          <div>
            <table class="w-full table-fixed text-left text-sm">
              <colgroup><col v-if="isOpen" class="w-[34px]" /><col class="w-[62px]" /><col /><col class="w-[132px]" /><col class="w-[150px]" /></colgroup>
              <thead class="bg-slate-50 text-xs uppercase text-slate-500">
                <tr><th v-if="isOpen" class="px-3 py-2"><input type="checkbox" :checked="allSelected" :title="tr('Chọn tất cả')" class="h-4 w-4 cursor-pointer" @change="toggleAll" /></th><th class="px-3 py-2">{{ tr('Giờ') }}</th><th class="px-3 py-2">{{ tr('Mã') }}</th><th class="px-3 py-2">{{ tr('Nhóm KH / Mã kho') }}</th><th class="px-3 py-2">{{ tr('Loại hình / Ngoại lệ') }}</th></tr>
              </thead>
              <tbody class="divide-y divide-slate-100">
                <tr v-if="!filtered.length"><td :colspan="isOpen ? 5 : 4" class="px-4 py-10 text-center text-slate-400">{{ tr('Chưa có kiện nào.') }}</td></tr>
                <tr v-for="i in filtered" :key="i.id" class="align-top" :class="selected.includes(i.id) ? 'bg-red-50/60' : ''">
                  <td v-if="isOpen" class="px-3 py-2"><input v-model="selected" type="checkbox" :value="i.id" :title="tr('Chọn kiện')" class="h-4 w-4 cursor-pointer" /></td>
                  <td class="px-3 py-2 text-xs text-slate-500">{{ fmtTime(i.scanned_at) }}</td>
                  <td class="break-all px-3 py-2 font-mono text-xs font-semibold">{{ i.barcode }}<span v-if="i.detected_carrier" class="ml-2 whitespace-nowrap rounded bg-slate-100 px-1.5 py-0.5 font-sans text-[10px] font-bold text-slate-600">{{ i.detected_carrier }}</span>
                    <span v-if="i.block_reason" class="ml-2 whitespace-nowrap rounded px-1.5 py-0.5 font-sans text-[10px] font-bold" :class="i.block_status === 'ACTIVE' ? 'bg-red-100 text-red-700' : 'bg-slate-100 text-slate-500 line-through'" :title="blockLabel(i.block_reason)">BLOCK</span>
                    <div v-if="i.block_reason" class="mt-0.5 font-sans text-[11px] font-semibold" :class="i.block_status === 'ACTIVE' ? 'text-red-600' : 'text-slate-400'">Block: {{ blockLabel(i.block_reason) }}<span v-if="i.block_status !== 'ACTIVE'"> {{ tr('(đã gỡ)') }}</span></div>
                    <span v-if="i.is_no_name" class="ml-2 whitespace-nowrap rounded bg-fuchsia-100 px-1.5 py-0.5 font-sans text-[10px] font-bold text-fuchsia-700">NO NAME</span>
                    <div v-if="i.is_no_name && i.tracks?.length > 1" class="mt-0.5 font-sans text-[11px] font-normal text-slate-500">{{ tr('Tracking trên tem: {0}', i.tracks.map((x) => x.barcode).join(' · ')) }}</div>
                    <div v-if="i.other_codes?.length" class="mt-0.5 font-sans text-[11px] font-normal text-slate-500">{{ tr('Mã tracking khác: {0}', i.other_codes.join(', ')) }}</div></td>
                  <td class="px-3 py-2">
                    <div class="font-medium">{{ i.customer_group || '—' }}</div>
                    <div class="break-all font-mono text-xs text-slate-500">{{ i.detected_warehouse_code || '—' }}</div>
                  </td>
                  <td class="space-y-1 px-3 py-2">
                    <button v-if="i.business_type" :disabled="!isOpen" :title="isOpen ? tr('Bấm để đổi loại hình') : ''" @click="toggleBusiness(i)"
                      class="rounded-full px-2.5 py-0.5 text-xs font-bold transition disabled:cursor-default"
                      :class="i.business_type === 'KINH_DOANH' ? 'bg-orange-100 text-accent-dark hover:bg-orange-200' : 'bg-slate-100 text-slate-600 hover:bg-slate-200'">
                      {{ i.business_type === 'KINH_DOANH' ? tr('Kinh doanh') : tr('Không kinh doanh') }}
                    </button>
                    <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
                      <a v-for="(u, k) in damagePhotos(i)" :key="u" :href="u" target="_blank" class="inline-flex items-center gap-0.5 text-xs font-semibold text-accent-dark hover:underline"><Camera class="h-3.5 w-3.5" />{{ tr('Ảnh') }}{{ damagePhotos(i).length > 1 ? k + 1 : '' }}</a>
                      <a v-for="(u, k) in i.label_photos" :key="u" :href="u" target="_blank" class="inline-flex items-center gap-0.5 text-xs font-semibold text-sky-700 hover:underline"><Tag class="h-3.5 w-3.5" />Label{{ i.label_photos.length > 1 ? k + 1 : '' }}</a>
                      <span v-if="!(i.label_photos || []).length" class="whitespace-nowrap text-xs font-bold text-red-600">{{ tr('⚠ Thiếu ảnh label') }}</span>
                      <label class="inline-flex cursor-pointer items-center gap-0.5 text-xs font-semibold text-slate-500 hover:text-navy" :title="tr('Chụp / tải ảnh label của kiện này')">
                        <ImagePlus class="h-3.5 w-3.5" />{{ tr('Ảnh label') }}
                        <input type="file" accept="image/*" capture="environment" class="hidden" @change="uploadLabel(i, $event)" />
                      </label>
                    </div>
                    <select :value="i.exception_status" :disabled="!isOpen" class="w-full rounded-md border bg-white px-1.5 py-1 text-xs" :class="i.exception_status === 'UNKNOWN' ? 'border-red-300 font-bold text-red-600' : 'border-slate-200'" @change="changeException(i, $event.target.value)">
                      <option value="NORMAL">{{ tr('Bình thường') }}</option><option value="UNKNOWN">{{ tr('Không xác định') }}</option><option value="DAMAGED">{{ tr('Hư hỏng') }}</option>
                      <option value="HOLDING">{{ tr('Đang giữ') }}</option><option value="BLOCKED">{{ tr('Bị chặn') }}</option>
                    </select>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
    <!-- Pop-up chan: da du 3 tracking khong co thong tin -> bat buoc quet QR END CODE -->
    <div v-if="endBlock && isOpen" class="fixed inset-0 z-[60] flex items-center justify-center bg-navy/80 p-4">
      <div class="card w-full max-w-sm space-y-3 p-6 text-center">
        <AlertTriangle class="mx-auto h-10 w-10 text-amber-500" />
        <h2 class="text-xl font-extrabold text-navy">{{ tr('Bắt buộc quét QR END CODE') }}</h2>
        <p class="text-sm text-slate-600">{{ tr('Tem này đã quét đủ 3 tracking nhưng không có thông tin trong danh sách. Hãy quét mã QR END CODE trước khi quét tem khác.') }}</p>
        <div class="font-mono text-xs text-slate-500">Tracking: {{ pendingTracks.map((t) => t.barcode).join(' · ') }}</div>
        <button class="btn-accent w-full" @click="code = 'ENDCODE'; submitScan()">{{ tr('Nhập END CODE (thao tác tay)') }}</button>
      </div>
    </div>

    <!-- Modal camera -->
    <div v-if="camOpen" class="fixed inset-0 z-50 flex items-center justify-center bg-navy/70 p-4">
      <div class="card w-full max-w-lg space-y-3 p-5">
        <div class="flex items-center justify-between">
          <h2 class="text-lg font-bold text-navy">{{ tr('Quét bằng camera') }}</h2>
          <button class="text-slate-400 hover:text-slate-600" @click="closeCamera"><X class="h-5 w-5" /></button>
        </div>
        <div class="relative overflow-hidden rounded-xl bg-black">
          <video ref="videoEl" class="aspect-video w-full object-cover" muted playsinline></video>
          <div class="pointer-events-none absolute inset-x-8 top-1/2 h-0.5 -translate-y-1/2 bg-accent/80"></div>
        </div>
        <p v-if="camError" class="text-sm text-red-500">{{ camError }}</p>
        <div v-if="last" class="rounded-lg px-3 py-2 text-center text-sm font-semibold text-white"
          :class="{ 'bg-emerald-500': last.kind === 'ok', 'bg-accent': last.kind === 'business', 'bg-slate-500': last.kind === 'unknown', 'bg-amber-500': last.kind === 'track', 'bg-fuchsia-600': last.kind === 'noname', 'bg-red-700': last.kind === 'blocked', 'bg-red-600': last.kind === 'duplicate' || last.kind === 'error' }">
          {{ last.kind === 'duplicate' ? tr('MÃ TRÙNG') : last.kind === 'error' ? (last.title || tr('LỖI')) : last.kind === 'track' ? `TING ${last.seq}/3` : last.kind === 'noname' ? 'NO NAME' : (last.item.customer_group || tr('KHÔNG XÁC ĐỊNH')) }} · <span class="font-mono">{{ last.item?.barcode || last.barcode }}</span>
        </div>
        <p class="text-xs text-slate-500">{{ tr('Đưa barcode vào giữa khung, giữ cách camera khoảng 15–25 cm. Quét xong mã nào sẽ tự ghi vào phiên, cứ đưa mã tiếp theo vào.') }}</p>
      </div>
    </div>
  </div>
</template>

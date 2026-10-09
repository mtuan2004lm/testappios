<script setup>
import { ref, reactive, watch, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { Plus, ScanLine, ChevronLeft, ChevronRight, X, Truck, Eye } from 'lucide-vue-next';
import { api, fmtDateTime } from '../api';
import CarrierLogo from '../components/CarrierLogo.vue';
import StatusBadge from '../components/StatusBadge.vue';

const router = useRouter();
const carriers = ['Amazon Logistics', 'Amazon Package', 'Amazon Pallet', 'DHL', 'FEDEX EXPRESS', 'FEDEX GROUND', 'FedEx', 'Other', 'UPS', 'USPS'];

const filters = reactive({ carrier: '', status: '', date: '' });
const sessions = ref([]);
const pagination = ref({ page: 1, limit: 10, total: 0, total_pages: 1 });
const loading = ref(false);
const error = ref('');

async function load(page = 1) {
  loading.value = true;
  error.value = '';
  try {
    const params = { page, limit: pagination.value.limit };
    for (const k of Object.keys(filters)) if (filters[k]) params[k] = filters[k];
    const res = await api.listSessions(params);
    sessions.value = res.data;
    pagination.value = res.pagination;
  } catch (e) {
    error.value = e.message;
  } finally {
    loading.value = false;
  }
}
watch(filters, () => load(1)); // doi bo loc -> ve trang 1
onMounted(() => load());

// ---- Modal tao phien moi ----
const showModal = ref(false);
const saving = ref(false);
const formError = ref('');
const form = reactive({ carrier_name: 'DHL', driver_name: '', license_plate: '', gate_code: 'OR_1 - D2', total_expected_packages: 0 });

async function createSession() {
  saving.value = true;
  formError.value = '';
  try {
    const res = await api.createSession({ ...form, total_expected_packages: Number(form.total_expected_packages) || 0 });
    showModal.value = false;
    router.push(`/receiving/sessions/${res.data.id}/scan`); // vao quet ngay
  } catch (e) {
    formError.value = e.message;
  } finally {
    saving.value = false;
  }
}
</script>

<template>
  <div class="space-y-5">
    <!-- Tieu de + nut tao phien -->
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div>
        <h1 class="text-2xl font-bold text-navy">Phiên tiếp nhận</h1>
        <p class="text-sm text-slate-500">Quản lý các lượt xe giao hàng đến kho</p>
      </div>
      <button class="btn-navy" @click="showModal = true"><Plus class="h-4 w-4" /> Bắt đầu phiên mới</button>
    </div>

    <!-- Thanh loc -->
    <div class="card grid gap-3 p-4 sm:grid-cols-3">
      <label class="text-xs font-semibold text-slate-500">Đơn vị vận chuyển
        <select v-model="filters.carrier" class="input mt-1">
          <option value="">Tất cả</option>
          <option v-for="c in carriers" :key="c" :value="c">{{ c }}</option>
        </select>
      </label>
      <label class="text-xs font-semibold text-slate-500">Trạng thái
        <select v-model="filters.status" class="input mt-1">
          <option value="">Tất cả</option>
          <option value="OPEN">OPEN</option>
          <option value="CLOSED">CLOSED</option>
        </select>
      </label>
      <label class="text-xs font-semibold text-slate-500">Ngày
        <input v-model="filters.date" type="date" class="input mt-1" />
      </label>
    </div>

    <!-- Bang du lieu -->
    <div class="card overflow-hidden">
      <div class="overflow-x-auto">
        <table class="w-full min-w-[900px] text-left text-sm">
          <thead class="bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
            <tr>
              <th class="px-4 py-3">Mã phiên</th><th class="px-4 py-3">Xe đến / rời</th><th class="px-4 py-3">Đơn vị vận chuyển</th>
              <th class="px-4 py-3">Người giao</th><th class="px-4 py-3">Biển số</th><th class="px-4 py-3">Cửa kho</th>
              <th class="px-4 py-3">Số kiện</th><th class="px-4 py-3">Trạng thái</th><th class="px-4 py-3 text-right">Thao tác</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-slate-100">
            <tr v-if="loading"><td colspan="9" class="px-4 py-10 text-center text-slate-400">Đang tải…</td></tr>
            <tr v-else-if="error"><td colspan="9" class="px-4 py-10 text-center text-red-500">{{ error }}</td></tr>
            <tr v-else-if="!sessions.length">
              <td colspan="9" class="px-4 py-14 text-center text-slate-400"><Truck class="mx-auto mb-2 h-8 w-8" />Chưa có phiên nào. Bấm “Bắt đầu phiên mới”.</td>
            </tr>
            <tr v-for="s in sessions" v-else :key="s.id" class="hover:bg-slate-50">
              <td class="px-4 py-3 font-bold text-navy">#{{ String(s.id).padStart(4, '0') }}</td>
              <td class="px-4 py-3 text-xs text-slate-600">
                <div>{{ fmtDateTime(s.arrival_time) }}</div>
                <div class="text-slate-400">{{ s.departure_time ? fmtDateTime(s.departure_time) : 'Chưa rời' }}</div>
              </td>
              <td class="px-4 py-3"><div class="flex items-center gap-2.5"><CarrierLogo :name="s.carrier_name" /><span class="font-semibold">{{ s.carrier_name }}</span></div></td>
              <td class="px-4 py-3">{{ s.driver_name || '—' }}</td>
              <td class="px-4 py-3 font-mono text-xs">{{ s.license_plate || '—' }}</td>
              <td class="px-4 py-3">{{ s.gate_code }}</td>
              <td class="px-4 py-3 font-semibold">{{ s.scanned_count }}<span class="text-slate-400"> / {{ s.total_expected_packages }}</span></td>
              <td class="px-4 py-3"><StatusBadge :status="s.status" /></td>
              <td class="px-4 py-3 text-right">
                <RouterLink v-if="s.status === 'OPEN'" :to="`/receiving/sessions/${s.id}/scan`" class="btn-accent !py-1.5"><ScanLine class="h-4 w-4" /> Quét tiếp</RouterLink>
                <RouterLink v-else :to="`/receiving/sessions/${s.id}/scan`" class="btn-outline !py-1.5"><Eye class="h-4 w-4" /> Xem</RouterLink>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- Phan trang goc phai duoi -->
      <div class="flex flex-wrap items-center justify-between gap-2 border-t border-slate-100 px-4 py-3 text-sm text-slate-500">
        <span>Tổng {{ pagination.total }} phiên</span>
        <div class="flex items-center gap-2">
          <button class="btn-outline !px-2 !py-1.5" :disabled="pagination.page <= 1" @click="load(pagination.page - 1)"><ChevronLeft class="h-4 w-4" /></button>
          <span>Trang <b class="text-navy">{{ pagination.page }}</b> / {{ pagination.total_pages }}</span>
          <button class="btn-outline !px-2 !py-1.5" :disabled="pagination.page >= pagination.total_pages" @click="load(pagination.page + 1)"><ChevronRight class="h-4 w-4" /></button>
        </div>
      </div>
    </div>

    <!-- Modal tao phien -->
    <div v-if="showModal" class="fixed inset-0 z-50 flex items-center justify-center bg-navy/60 p-4" @click.self="showModal = false">
      <form class="card w-full max-w-lg space-y-4 p-6" @submit.prevent="createSession">
        <div class="flex items-center justify-between">
          <h2 class="text-lg font-bold text-navy">Bắt đầu phiên mới</h2>
          <button type="button" class="text-slate-400 hover:text-slate-600" @click="showModal = false"><X class="h-5 w-5" /></button>
        </div>
        <div class="grid gap-3 sm:grid-cols-2">
          <label class="text-xs font-semibold text-slate-500">Đơn vị vận chuyển *
            <select v-model="form.carrier_name" class="input mt-1"><option v-for="c in carriers" :key="c">{{ c }}</option></select>
          </label>
          <label class="text-xs font-semibold text-slate-500">Cửa kho
            <input v-model="form.gate_code" class="input mt-1" maxlength="20" />
          </label>
          <label class="text-xs font-semibold text-slate-500">Người giao
            <input v-model="form.driver_name" class="input mt-1" maxlength="100" />
          </label>
          <label class="text-xs font-semibold text-slate-500">Biển số xe
            <input v-model="form.license_plate" class="input mt-1" maxlength="50" />
          </label>
          <label class="text-xs font-semibold text-slate-500 sm:col-span-2">Số kiện của phiên này (nhập tay)
            <input v-model="form.total_expected_packages" type="number" min="0" class="input mt-1" placeholder="VD: 25 — có thể sửa lại khi đang quét" />
          </label>
        </div>
        <p v-if="formError" class="text-sm text-red-500">{{ formError }}</p>
        <div class="flex justify-end gap-2">
          <button type="button" class="btn-outline" @click="showModal = false">Huỷ</button>
          <button class="btn-navy" :disabled="saving">{{ saving ? 'Đang tạo…' : 'Bắt đầu quét' }}</button>
        </div>
      </form>
    </div>
  </div>
</template>

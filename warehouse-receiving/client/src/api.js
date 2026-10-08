// Client goi API nho gon. Loi tra ve la ApiError co .status, .code, .data
export class ApiError extends Error {
  constructor(status, code, message, data) {
    super(message);
    this.status = status;
    this.code = code;
    this.data = data;
  }
}

async function request(method, url, body) {
  const res = await fetch(`/api/v1${url}`, {
    method,
    headers: body ? { 'Content-Type': 'application/json' } : undefined,
    body: body ? JSON.stringify(body) : undefined,
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) throw new ApiError(res.status, json.error?.code, json.error?.message || 'Lỗi không xác định', json.data);
  return json;
}

export const api = {
  listSessions: (params) => request('GET', `/receiving/sessions?${new URLSearchParams(params)}`),
  createSession: (body) => request('POST', '/receiving/sessions', body),
  getSession: (id) => request('GET', `/receiving/sessions/${id}`),
  scan: (id, body) => request('POST', `/receiving/sessions/${id}/scan`, body),
  updateExpected: (id, total_expected_packages) => request('PATCH', `/receiving/sessions/${id}`, { total_expected_packages }),
  finalize: (id) => request('PATCH', `/receiving/sessions/${id}/finalize`),
  closeSession: (id) => request('PATCH', `/receiving/sessions/${id}/close`),
  toggleBusiness: (itemId) => request('PATCH', `/scanned-items/${itemId}/toggle-business-type`),
  listTracking: (params) => request('GET', `/tracking-codes?${new URLSearchParams(params)}`),
  importTracking: (items) => request('POST', '/tracking-codes/bulk', { items }),
  generateTracking: (count) => request('POST', '/tracking-codes/generate', { count }),
  deleteTracking: (id) => request('DELETE', `/tracking-codes/${id}`),
  listProducts: (params) => request('GET', `/products?${new URLSearchParams(params)}`),
  createProduct: (body) => request('POST', '/products', body),
  updateProduct: (id, body) => request('PUT', `/products/${id}`, body),
  deleteProduct: (id) => request('DELETE', `/products/${id}`),
  removeProductImage: (id) => request('DELETE', `/products/${id}/image`),
  uploadProductImage: async (id, file) => {
    const res = await fetch(`/api/v1/products/${id}/image`, { method: 'POST', headers: { 'Content-Type': file.type || 'image/jpeg' }, body: file });
    const json = await res.json().catch(() => ({}));
    if (!res.ok) throw new ApiError(res.status, json.error?.code, json.error?.message || 'Không tải được ảnh');
    return json;
  },
  listFlights: (params) => request('GET', `/flights?${new URLSearchParams(params)}`),
  createFlight: (body) => request('POST', '/flights', body),
  updateFlight: (id, body) => request('PUT', `/flights/${id}`, body),
  setFlightStatus: (id, status) => request('PATCH', `/flights/${id}/status`, { status }),
  deleteFlight: (id) => request('DELETE', `/flights/${id}`),
  listHolds: (params) => request('GET', `/holds?${new URLSearchParams(params)}`),
  createHold: (body) => request('POST', '/holds', body),
  patchHold: (id, body) => request('PATCH', `/holds/${id}`, body),
  bulkHolds: (body) => request('PATCH', '/holds/bulk', body),
  deleteHold: (id) => request('DELETE', `/holds/${id}`),
  listBins: (params) => request('GET', `/bin-locations?${new URLSearchParams(params || {})}`),
  createBin: (body) => request('POST', '/bin-locations', body),
  bulkBins: (items) => request('POST', '/bin-locations/bulk', { items }),
  updateBin: (id, body) => request('PUT', `/bin-locations/${id}`, body),
  deleteBin: (id) => request('DELETE', `/bin-locations/${id}`),
  setException: (itemId, exception_status) => request('PATCH', `/scanned-items/${itemId}/exception`, { exception_status }),
};

export const fmtTime = (iso) => (iso ? new Date(iso).toLocaleTimeString('vi-VN', { hour: '2-digit', minute: '2-digit', second: '2-digit' }) : '—');
export const fmtDateTime = (iso) => (iso ? new Date(iso).toLocaleString('vi-VN', { dateStyle: 'short', timeStyle: 'short' }) : '—');

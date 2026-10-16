// Đa ngôn ngữ Việt / Anh. Khóa của bản dịch chính là câu tiếng Việt gốc, nên thiếu bản dịch thì vẫn hiện tiếng Việt.
//   tr('Tổng {0} phiên', n)  ->  "Tổng 5 phiên"  /  "5 sessions in total" (khi chọn EN)
import { ref } from 'vue';
import en from './locales/en.js';

const KEY = 'lang';
const load = () => {
  try { const v = localStorage.getItem(KEY); if (v === 'en' || v === 'vi') return v; } catch (e) { /* bỏ qua */ }
  return 'vi';
};

export const lang = ref(load());

export function setLang(v) {
  lang.value = v === 'en' ? 'en' : 'vi';
  try { localStorage.setItem(KEY, lang.value); } catch (e) { /* bỏ qua */ }
  document.documentElement.lang = lang.value;
}

export function tr(key, ...args) {
  let s = lang.value === 'en' && Object.prototype.hasOwnProperty.call(en, key) ? en[key] : key;
  if (args.length) args.forEach((a, i) => { s = s.split(`{${i}}`).join(a); });
  return s;
}

/** Mã locale cho định dạng ngày giờ. */
export const locale = () => (lang.value === 'en' ? 'en-US' : 'vi-VN');

// Thông báo từ server (tiếng Việt): tra bản dịch cố định, hoặc theo mẫu nếu có chèn biến.
const PATTERNS = [
  [/^Mã (.+) vừa quét ở tem này$/, 'Code {0} was just scanned on this label'],
  [/^Mã (.+) đã được quét trong phiên này$/, 'Code {0} has already been scanned in this session'],
  [/^Mã vị trí (.+) đã tồn tại$/, 'Bin code {0} already exists'],
  [/^Tối đa (\d+) mã mỗi lần nhập$/, 'At most {0} codes per import'],
  [/^Regex nhận biết sai: (.+)$/, 'Invalid detection regex: {0}'],
  [/^Regex rút mã sai: (.+)$/, 'Invalid extraction regex: {0}'],
  [/^(.+) phải là số nguyên từ 0 trở lên$/, '{0} must be an integer ≥ 0'],
  [/^(.+) không hợp lệ$/, '{0} is invalid'],
  [/^BLOCK – (.+)$/, 'BLOCK – {0}'],
];
export function trMsg(m) {
  if (lang.value !== 'en' || !m) return m;
  if (Object.prototype.hasOwnProperty.call(en, m)) return en[m];
  for (const [re, t] of PATTERNS) {
    const mm = String(m).match(re);
    if (mm) return t.replace(/\{(\d)\}/g, (_, i) => trMsg(mm[+i + 1]));
  }
  return m;
}

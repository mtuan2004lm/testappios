// Chuan hoa ma vach va suy ra "ma ung vien" theo dinh dang tung hang van chuyen (bang tracking_formats)
const normalize = (s) => String(s || '').replace(/[\x00-\x1F\x7F]/g, '').replace(/\s/g, '').toUpperCase();

// Doan hang tu ten hang cua phien (DHL, FedEx, FEDEX GROUND, Amazon Pallet, UPS, USPS, Other...)
function carrierFromName(name) {
  const n = String(name || '').toUpperCase();
  if (n.includes('FEDEX')) return 'FEDEX';
  if (n.includes('AMAZON')) return 'AMAZON';
  if (n.includes('USPS')) return 'USPS';
  if (n.includes('UPS')) return 'UPS';
  if (n.includes('DHL')) return 'DHL';
  return null;
}

// Ap mot dinh dang len ma da chuan hoa -> ma ung vien hoac null neu khong khop
function applyFormat(f, code) {
  let re;
  try { re = new RegExp(f.detect_regex); } catch { return null; }
  if (!re.test(code)) return null;
  const n = parseInt(f.extract_param, 10);
  switch (f.extract_mode) {
    case 'LAST': return Number.isInteger(n) && n > 0 && code.length >= n ? code.slice(-n) : null;
    case 'DROP_FIRST': return Number.isInteger(n) && n > 0 && code.length > n ? code.slice(n) : null;
    case 'REGEX': {
      try { const m = code.match(new RegExp(f.extract_param)); return m ? (m[1] || m[0]) : null; } catch { return null; }
    }
    default: return code;
  }
}

// Phien chi nhan ma cua hang da chon: ten hang (vd "FEDEX GROUND", "Amazon Pallet") -> khoa hang. "Other" / ten la -> null (khong gioi han)
const sessionCarrierKey = carrierFromName;

// Cac hang ma ma nay co the thuoc ve (theo regex nhan biet cua cac dinh dang dang bat)
function detectCarriers(code, formats) {
  const out = [];
  for (const f of formats) { try { if (new RegExp(f.detect_regex).test(code) && !out.includes(f.carrier)) out.push(f.carrier); } catch { /* bo qua regex loi */ } }
  return out;
}

// Tra ve { code, candidates: [{value, carrier, format}] } - ma goc luon la ung vien dau tien
function candidatesFor(barcode, formats) {
  const code = normalize(barcode);
  const list = [{ value: code, carrier: null, format: null }];
  const seen = new Set([code]);
  for (const f of formats) {
    const v = applyFormat(f, code);
    if (!v) continue;
    if (!seen.has(v)) { seen.add(v); list.push({ value: v, carrier: f.carrier, format: f.name }); }
    else if (v === code) list[0] = { ...list[0], carrier: list[0].carrier || f.carrier, format: list[0].format || f.name };
  }
  // Ma dang ZIP+4 (vd 97220-2141): ma vach thuong khong co dau '-', 420+ZIP9 la ma dinh tuyen USPS
  const extra = (v, carrier, format) => { if (v && !seen.has(v)) { seen.add(v); list.push({ value: v, carrier, format }); } };
  for (const c of [...list]) {
    const v = c.value;
    let m;
    if ((m = v.match(/^420(\d{5})(\d{4})$/))) extra(`${m[1]}-${m[2]}`, 'USPS', 'ZIP+4 (420 + ZIP9)');
    if ((m = v.match(/^(\d{5})(\d{4})$/))) extra(`${m[1]}-${m[2]}`, c.carrier, 'ZIP+4');
    if (v.includes('-')) extra(v.replace(/-/g, ''), c.carrier, 'bỏ dấu -');
  }
  return { code, candidates: list };
}

async function loadFormats(db) {
  return (await db.query('SELECT * FROM tracking_formats WHERE is_active = TRUE ORDER BY sort_order, id')).rows;
}

// Doi chieu ma vach voi Danh sach mat hang. Tra ve { product, carrier, method, candidates, code } (product = null neu khong khop)
// method: EXACT (khop nguyen ma) | DERIVED (khop ma rut ra theo dinh dang hang) | CONTAINS (du phong: ma trong danh sach nam trong ma vach)
async function matchProduct(q, barcode, sessionCarrierName) {
  const formats = await loadFormats(q);
  const { code, candidates } = candidatesFor(barcode, formats);
  const values = candidates.map((c) => c.value);
  const hint = carrierFromName(sessionCarrierName);
  let product = (await q.query(
    `SELECT id, name, tracking_code, alt_code, alt_code2, tracking_norm, alt_norm, alt2_norm FROM products WHERE tracking_norm = ANY($1) OR alt_norm = ANY($1) OR alt2_norm = ANY($1)
      ORDER BY (tracking_norm = $2 OR alt_norm = $2 OR alt2_norm = $2) DESC, id LIMIT 1`, [values, code])).rows[0];
  let method = null, hit = null;
  if (product) {
    hit = candidates.find((c) => c.value === product.tracking_norm || c.value === product.alt_norm || c.value === product.alt2_norm);
    method = hit.value === code ? 'EXACT' : 'DERIVED';
  } else {
    // Du phong cho dinh dang chua khai bao: ma trong danh sach (>= 10 ky tu) nam trong ma vach
    product = (await q.query(
      `SELECT id, name, tracking_code, alt_code, alt_code2, tracking_norm, alt_norm, alt2_norm FROM products
        WHERE (length(tracking_norm) >= 10 AND strpos($1, tracking_norm) > 0) OR (length(alt_norm) >= 10 AND strpos($1, alt_norm) > 0) OR (length(alt2_norm) >= 10 AND strpos($1, alt2_norm) > 0)
        ORDER BY length(tracking_norm) DESC LIMIT 1`, [code])).rows[0];
    if (product) method = 'CONTAINS';
  }
  // Hang van chuyen hien thi = hang cua CHINH ma da khop (khong phu thuoc hang cua phien).
  // Uu tien hang cua dinh dang da rut ra ma; neu khop nguyen ma thi doan theo dang ma, hang cua phien chi dung de chon khi ma khop nhieu hang.
  const sessionCarrier = sessionCarrierKey(sessionCarrierName);
  let detected = null;
  if (product) {
    if (hit && hit.carrier && method === 'DERIVED') detected = hit.carrier;
    else {
      const matchedCode = hit ? hit.value : product.tracking_norm;
      const list = detectCarriers(matchedCode, formats);
      detected = (sessionCarrier && list.includes(sessionCarrier)) ? sessionCarrier : (list[0] || null);
      if (!detected) { const l2 = detectCarriers(product.tracking_norm, formats); detected = (sessionCarrier && l2.includes(sessionCarrier)) ? sessionCarrier : (l2[0] || null); }
    }
  } else {
    const list = detectCarriers(code, formats);
    detected = list[0] || null;   // khong khop mat hang: chi de tham khao khi thu ma
  }
  const matched = product ? (candidates.find((c) => c.value === product.tracking_norm || c.value === product.alt_norm || c.value === product.alt2_norm)?.value || product.tracking_norm) : null;
  return { product, carrier: detected, method, candidates, code, matched };
}

module.exports = { normalize, carrierFromName, sessionCarrierKey, candidatesFor, matchProduct, loadFormats };

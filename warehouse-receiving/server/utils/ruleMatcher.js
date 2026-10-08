// Khop chuoi do OCR/quet duoc voi bo quy tac warehouse_rules
// Quy tac duoc duyet theo id tang dan, quy tac dau tien khop se thang.

function matchRule(text, rules) {
  const value = String(text || '').trim();
  if (!value) return null;
  for (const rule of rules) {
    try {
      // 'i': khong phan biet hoa thuong vi OCR co the tra ve chu thuong
      // Tren nhan chu "SG HUE DOFA168" co the in khoang trang trong khi quy tac viet "SG HUE_DOFA168"
      // -> coi dau gach duoi va khoang trang trong quy tac la tuong duong
      const re = new RegExp(rule.pattern_regex.replace(/[_ ]/g, '[_ ]'), 'i');
      if (re.test(value)) return rule;
    } catch (e) {
      // Regex trong DB sai cu phap -> bo qua quy tac do, khong lam hong ca luot quet
      console.warn(`[ruleMatcher] Bo qua rule #${rule.id}, regex loi: ${e.message}`);
    }
  }
  return null;
}

module.exports = { matchRule };

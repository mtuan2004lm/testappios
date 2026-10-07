const express = require('express');
const router = express.Router();
const warehouse = require('../controllers/warehouseController');
const sessions = require('../controllers/sessionController');
const scan = require('../controllers/scanController');
const items = require('../controllers/itemController');
const tracking = require('../controllers/trackingController');

router.get('/warehouse/rules', warehouse.listRules);

router.get('/receiving/sessions', sessions.listSessions);
router.post('/receiving/sessions', sessions.createSession);
router.get('/receiving/sessions/:id', sessions.getSession);
router.post('/receiving/sessions/:id/scan', scan.scan);
router.patch('/receiving/sessions/:id', sessions.updateExpected);
router.post('/receiving/sessions/:id/classify', scan.classify);
router.patch('/receiving/sessions/:id/finalize', sessions.finalizeCount);
router.patch('/receiving/sessions/:id/close', sessions.closeSession);

router.patch('/scanned-items/:id/toggle-business-type', items.toggleBusinessType);
router.patch('/scanned-items/:id/exception', items.setException);
// Anh tho (image/*) toi da 10MB
router.post('/scanned-items/:id/damage-photo', express.raw({ type: 'image/*', limit: '10mb' }), items.addDamagePhoto);

router.get('/tracking-codes', tracking.list);
router.post('/tracking-codes/bulk', tracking.bulk);
router.post('/tracking-codes/generate', tracking.generate);
router.delete('/tracking-codes/:id', tracking.remove);

module.exports = router;

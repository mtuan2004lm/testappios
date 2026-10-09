const express = require('express');
const router = express.Router();
const warehouse = require('../controllers/warehouseController');
const sessions = require('../controllers/sessionController');
const scan = require('../controllers/scanController');
const items = require('../controllers/itemController');
const tracking = require('../controllers/trackingController');
const products = require('../controllers/productController');
const flights = require('../controllers/flightController');
const bins = require('../controllers/binLocationController');
const holds = require('../controllers/holdController');
const formats = require('../controllers/formatController');

router.get('/warehouse/rules', warehouse.listRules);

router.get('/receiving/sessions', sessions.listSessions);
router.post('/receiving/sessions', sessions.createSession);
router.get('/receiving/sessions/:id', sessions.getSession);
router.post('/receiving/sessions/:id/scan', scan.scan);
router.post('/receiving/sessions/:id/scan-fail', scan.scanFail);
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

router.get('/products', products.list);
router.post('/products', products.create);
router.put('/products/:id', products.update);
router.delete('/products/:id', products.remove);
router.post('/products/:id/image', express.raw({ type: 'image/*', limit: '10mb' }), products.setImage);
router.delete('/products/:id/image', products.removeImage);

router.get('/flights', flights.list);
router.post('/flights', flights.create);
router.put('/flights/:id', flights.update);
router.patch('/flights/:id/status', flights.setStatus);
router.delete('/flights/:id', flights.remove);

router.get('/bin-locations', bins.list);
router.post('/bin-locations', bins.create);
router.post('/bin-locations/bulk', bins.bulk);
router.put('/bin-locations/:id', bins.update);
router.delete('/bin-locations/:id', bins.remove);

router.get('/holds', holds.list);
router.post('/holds', holds.create);
router.patch('/holds/bulk', holds.bulk);
router.patch('/holds/:id', holds.patch);
router.delete('/holds/:id', holds.remove);

router.get('/tracking-formats', formats.list);
router.post('/tracking-formats', formats.create);
router.post('/tracking-formats/test', formats.test);
router.put('/tracking-formats/:id', formats.update);
router.delete('/tracking-formats/:id', formats.remove);

module.exports = router;

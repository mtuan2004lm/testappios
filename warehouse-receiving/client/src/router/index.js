import { createRouter, createWebHistory } from 'vue-router';
import SessionList from '../views/SessionList.vue';
import SessionScan from '../views/SessionScan.vue';
import Placeholder from '../views/Placeholder.vue';
import TrackingCodes from '../views/TrackingCodes.vue';

export default createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', redirect: '/receiving/sessions' },
    { path: '/receiving/sessions', name: 'sessions', component: SessionList },
    { path: '/receiving/sessions/:id/scan', name: 'scan', component: SessionScan, props: true },
    // Cac tab chua co chuc nang: hien trang tam
    { path: '/items', name: 'items', component: TrackingCodes },
    { path: '/flights', component: Placeholder, props: { title: 'Chuyến bay' } },
    { path: '/reports', component: Placeholder, props: { title: 'Báo cáo tracking' } },
  ],
});

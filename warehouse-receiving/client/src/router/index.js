import { createRouter, createWebHistory } from 'vue-router';
import SessionList from '../views/SessionList.vue';
import SessionScan from '../views/SessionScan.vue';
import Placeholder from '../views/Placeholder.vue';
import ItemsList from '../views/ItemsList.vue';
import FlightsManagement from '../views/FlightsManagement.vue';
import HoldsList from '../views/HoldsList.vue';
import BinLocations from '../views/BinLocations.vue';
import TrackingFormats from '../views/TrackingFormats.vue';
import TrackingCodes from '../views/TrackingCodes.vue';

export default createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', redirect: '/receiving/sessions' },
    { path: '/receiving/sessions', name: 'sessions', component: SessionList },
    { path: '/receiving/sessions/:id/scan', name: 'scan', component: SessionScan, props: true },
    { path: '/receiving/detained', name: 'detained', component: HoldsList },
    { path: '/receiving/bin-locations', name: 'bins', component: BinLocations },
    { path: '/receiving/tracking-formats', name: 'formats', component: TrackingFormats },
    // Cac tab chua co chuc nang: hien trang tam
    { path: '/items', name: 'items', component: ItemsList },
    { path: '/flights', name: 'flights', component: FlightsManagement },
    { path: '/flights/waiting', component: Placeholder, props: { title: 'Chờ vào box' } },
    { path: '/reports', name: 'reports', component: TrackingCodes },
  ],
});

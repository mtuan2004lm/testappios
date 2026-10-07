<script setup>
import AppNavbar from './components/AppNavbar.vue';
</script>

<template>
  <div class="flex min-h-screen flex-col">
    <AppNavbar />
    <main class="mx-auto w-full max-w-[1400px] flex-1 px-4 py-6 sm:px-6">
      <RouterView />
    </main>
  </div>
</template>

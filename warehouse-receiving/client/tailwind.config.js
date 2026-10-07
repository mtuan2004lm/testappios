/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{vue,js}'],
  theme: {
    extend: {
      colors: { navy: { DEFAULT: '#0a192f', 700: '#112240', 600: '#1d3557' }, accent: { DEFAULT: '#f97316', dark: '#ea580c' } },
      fontFamily: { sans: ['Inter', 'system-ui', 'sans-serif'] },
    },
  },
  plugins: [],
};

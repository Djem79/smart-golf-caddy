import { defineConfig } from 'vitest/config'

// Отдельный TS-проект (functions/) со своим package.json — без этого файла
// vitest, запущенный из functions/, поднимается по дереву каталогов и
// подхватывает корневой vite.config.ts (jsdom + setupFiles веб-проекта),
// что здесь не применимо: functions — чистый Node/Admin-SDK код без DOM.
export default defineConfig({
  test: {
    environment: 'node',
    include: ['src/**/*.test.ts'],
  },
})

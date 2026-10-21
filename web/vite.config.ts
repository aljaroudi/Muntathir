import { defineConfig } from "vite-plus"

export default defineConfig({
  staged: {
    '*': 'vp check --fix'
  },
  fmt: {
    ignorePatterns: ["dist/**", ".astro/**", "public/**"],
    semi: false,
    trailingComma: "es5",
    arrowParens: "avoid",
  },
  lint: {
    ignorePatterns: ["dist/**", ".astro/**", "public/**"],
  },
})

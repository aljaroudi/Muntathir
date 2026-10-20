import { defineConfig } from "vite-plus"

export default defineConfig({
  fmt: {
    ignorePatterns: ["dist/**", ".astro/**", "public/**", "scripts/fonts/**"],
    semi: false,
    trailingComma: "es5",
    arrowParens: "avoid",
  },
  lint: {
    ignorePatterns: ["dist/**", ".astro/**", "public/**"],
  },
})

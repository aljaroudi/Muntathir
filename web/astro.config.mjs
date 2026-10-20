// @ts-check
import { defineConfig, fontProviders } from "astro/config"
import tailwindcss from "@tailwindcss/vite"

export default defineConfig({
  site: new URL("https://منتظر.com").href,
  output: "static",
  fonts: [
    {
      provider: fontProviders.google(),
      name: "Inter",
      cssVariable: "--font-inter",
      weights: [400, 500, 600],
      subsets: ["latin"],
      styles: ["normal"],
    },
    {
      provider: fontProviders.google(),
      name: "Noto Sans Arabic",
      cssVariable: "--font-arabic",
      weights: [400, 500, 600],
      subsets: ["arabic", "latin"],
      styles: ["normal"],
    },
    {
      provider: fontProviders.google(),
      name: "Amiri",
      cssVariable: "--font-amiri",
      weights: [400],
      subsets: ["arabic"],
      styles: ["normal"],
    },
  ],
  trailingSlash: "always",
  i18n: {
    defaultLocale: "ar",
    locales: ["ar", "en"],
    routing: { prefixDefaultLocale: false },
  },
  vite: { plugins: [tailwindcss()] },
})

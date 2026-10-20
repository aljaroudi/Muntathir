export const site = new URL("https://منتظر.com")
export const appStore = "https://apps.apple.com/app/muntathir/id6824304362"
export const paths = { ar: "/", en: "/en/" } as const
export type Locale = keyof typeof paths
export const isPreview = process.env.VERCEL_ENV === "preview"

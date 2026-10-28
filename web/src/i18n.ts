import type { Locale } from "./site"

const en = {
  name: "Muntathir",
  title: "Muntathir: Prayer times, Quran, and Hijri calendar",
  description:
    "Prayer times, daily Quran verses, the Hijri calendar, and Qibla. An app in 15 languages for iPhone, iPad, and Apple Watch.",
  skip: "Skip to content",
  nav: { language: "Choose language" },
  hero: {
    first: "Prayer and",
    second: "daily remembrance.",
    eyebrow: "Prayer · Quran · Hijri calendar",
    text: "Prayer times, a Quran verse each day, the Hijri calendar, and the direction of the Qibla. Together in a simple app.",
    cta: "Download Muntathir from the App Store",
  },
  preview: {
    label: "Example prayer times and a daily Quran verse",
    today: "Muntathir",
    verseLabel: "A verse from the Quran",
    verse: "Indeed, with hardship comes ease.",
    reference: "94:5",
    prayers: ["Fajr", "Dhuhr", "Maghrib"],
    times: ["4:42am", "12:08pm", "5:36pm"],
  },
  features: {
    title: "In the app",
    items: [
      {
        title: "Prayer times",
        text: "Choose a calculation method and set prayer reminders for your location.",
      },
      { title: "Daily Quran verse", text: "Read a verse each day and share it as a card." },
      {
        title: "Hijri calendar",
        text: "Follow Islamic dates and observances, with adjustable month starts.",
      },
      { title: "Qibla", text: "Find the direction of prayer with a compass view." },
    ],
  },
  calendar: {
    title: "Islamic calendar subscription",
    subscribe: "Subscribe to calendar",
    description:
      "Dates follow Middle East naked-eye confirmations, with Umm al-Qura calculations until confirmed. Subscribe to receive date corrections; your calendar app controls refresh timing.",
  },
  companions:
    "Available in 15 languages, including Arabic and English. Made for iPhone and iPad, with an Apple Watch companion and Home Screen widgets.",
  faq: {
    title: "A few useful details",
    items: [
      {
        q: "Can I adjust prayer times?",
        a: "You can choose the prayer calculation method in the app’s settings.",
      },
      {
        q: "Which calendar verification methods are supported?",
        a: "Choose the system calendar, local naked-eye sighting for the Middle East, or government announcements from Saudi Arabia, Kuwait, Bahrain, Oman, the UAE, or Qatar. Adjust individual months by up to two days.",
      },
      {
        q: "How does the Hijri calendar stay accurate?",
        a: "Muntathir automatically corrects Hijri month starts based on your preferred verification method when matching confirmations are available. Until then, dates follow the calculated Umm Al-Qura calendar.",
      },
    ],
  },
  footer: {
    top: "Back to top",
  },
}

const ar: typeof en = {
  name: "منتظِر",
  title: "منتظِر — مواقيت الصلاة والقرآن والتقويم الهجري",
  description:
    "مواقيت الصلاة وآيات قرآنية يومية والتقويم الهجري واتجاه القبلة. تطبيق بـ١٥ لغة لأجهزة iPhone وiPad وApple Watch.",
  skip: "انتقل إلى المحتوى",
  nav: { language: "اختر اللغة" },
  hero: {
    first: "صلاتك،",
    second: "وذكرُك اليومي.",
    eyebrow: "الصلاة · القرآن · التقويم الهجري",
    text: "مواقيت الصلاة، وآية قرآنية كل يوم، والتقويم الهجري، واتجاه القبلة. في تطبيق بسيط يرافق يومك.",
    cta: "تحميل تطبيق مُنتظِر من متجر التطبيقات",
  },
  preview: {
    label: "أوقات صلاة توضيحية وآية من القرآن الكريم",
    today: "منتظِر",
    verseLabel: "آية اليوم",
    verse: "إِنَّ مَعَ الْعُسْرِ يُسْرًا",
    reference: "الشرح ٥",
    prayers: ["الفجر", "الظهر", "المغرب"],
    times: ["٤:٤٢ ص", "١٢:٠٨ م", "٥:٣٦ م"],
  },
  features: {
    title: "في التطبيق",
    items: [
      { title: "مواقيت الصلاة", text: "اختر طريقة الحساب واضبط تنبيهات الصلاة حسب موقعك." },
      { title: "آية كل يوم", text: "اقرأ آية قرآنية يوميًا وشاركها في بطاقة." },
      {
        title: "التقويم الهجري",
        text: "تابع التواريخ والمناسبات الإسلامية، مع إمكانية ضبط بدايات الأشهر.",
      },
      { title: "اتجاه القبلة", text: "اعرف اتجاه الصلاة من خلال بوصلة واضحة." },
    ],
  },
  calendar: {
    title: "الاشتراك في تقويم المناسبات الإسلامية",
    subscribe: "اشترك في التقويم",
    description:
      "تتبع التواريخ تأكيدات الرؤية بالعين المجردة للشرق الأوسط، وحسابات أم القرى حتى ورود التأكيد. اشترك لتصلك تصحيحات التواريخ؛ ويتحكم تطبيق التقويم في مواعيد التحديث.",
  },
  companions:
    "متوفر بـ١٥ لغة، منها العربية والإنجليزية. لأجهزة \u2066iPhone\u2069 و\u2066iPad\u2069، مع تطبيق مرافق لساعة \u2066Apple Watch\u2069 وأدوات للشاشة الرئيسية.",
  faq: {
    title: "تفاصيل مفيدة",
    items: [
      {
        q: "هل يمكنني ضبط مواقيت الصلاة؟",
        a: "يمكنك اختيار طريقة حساب مواقيت الصلاة من إعدادات التطبيق.",
      },
      {
        q: "ما طرق التحقق من بداية الشهر المدعومة؟",
        a: "يمكنك اختيار تقويم النظام، أو الرؤية بالعين المجردة لمنطقة الشرق الأوسط، أو الإعلانات الرسمية للسعودية والكويت والبحرين وعُمان والإمارات وقطر. ويمكنك تعديل كل شهر بما يصل إلى يومين.",
      },
      {
        q: "كيف يحافظ التطبيق على دقة التقويم الهجري؟",
        a: "يصحّح منتظِر بدايات الأشهر الهجرية تلقائيًا وفق طريقة التحقق التي تفضّلها عند توفّر تأكيدات مطابقة. وحتى ذلك الحين، تتبع التواريخ حسابات تقويم أم القرى.",
      },
    ],
  },
  footer: {
    top: "العودة إلى الأعلى",
  },
}

export const translations: Record<Locale, typeof en> = { ar, en }

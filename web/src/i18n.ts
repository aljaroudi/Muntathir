import type { Locale } from "./site"

const en = {
  name: "Muntathir",
  title: "Muntathir: Prayer times, Quran, and Hijri calendar",
  description:
    "Prayer times, daily Quran verses, the Hijri calendar, and Qibla. An Arabic and English app for iPhone, iPad, and Apple Watch.",
  skip: "Skip to content",
  nav: { language: "Choose language" },
  hero: {
    first: "Prayer and",
    second: "daily remembrance.",
    eyebrow: "Prayer · Quran · Hijri calendar",
    text: "Prayer times, a Quran verse each day, the Hijri calendar, and the direction of the Qibla. Together in a simple app.",
    cta: "View on the App Store",
    note: "Coming soon. The App Store listing is not available yet.",
  },
  preview: {
    label: "Example prayer times and a daily Quran verse",
    today: "Muntathir",
    verseLabel: "A verse from the Quran",
    verse: "فَإِنَّ مَعَ الْعُسْرِ يُسْرًا",
    reference: "Ash-Sharh · 94:5",
    prayers: ["Fajr", "Dhuhr", "Maghrib"],
    times: ["04:42", "12:08", "17:36"],
    example: "Example times, not a live prayer schedule.",
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
  companions:
    "Available in Arabic and English. Made for iPhone and iPad, with an Apple Watch companion and Home Screen widgets.",
  faq: {
    title: "A few useful details",
    items: [
      {
        q: "Can I adjust prayer times and Hijri dates?",
        a: "You can choose the prayer calculation method and adjust Hijri month starts to match the dates you follow.",
      },
      {
        q: "How do prayer reminders work?",
        a: "Enable notifications on your device. Open the app regularly so iOS can keep upcoming reminders scheduled.",
      },
      {
        q: "Where can I download Muntathir?",
        a: "The App Store listing linked above will become available at launch. Android and a browser app are not available yet.",
      },
    ],
  },
  footer: {
    top: "Back to top",
    trademark:
      "Apple, iPhone, iPad, and Apple Watch are trademarks of Apple Inc. App Store is a service mark of Apple Inc.",
  },
}

const ar: typeof en = {
  name: "منتظِر",
  title: "منتظِر — مواقيت الصلاة والقرآن والتقويم الهجري",
  description:
    "مواقيت الصلاة وآيات قرآنية يومية والتقويم الهجري واتجاه القبلة. تطبيق بالعربية والإنجليزية لأجهزة iPhone وiPad وApple Watch.",
  skip: "انتقل إلى المحتوى",
  nav: { language: "اختر اللغة" },
  hero: {
    first: "صلاتك،",
    second: "وذكرُك اليومي.",
    eyebrow: "الصلاة · القرآن · التقويم الهجري",
    text: "مواقيت الصلاة، وآية قرآنية كل يوم، والتقويم الهجري، واتجاه القبلة. في تطبيق بسيط يرافق يومك.",
    cta: "عرض في App Store",
    note: "قريبًا. صفحة التطبيق على المتجر غير متاحة بعد.",
  },
  preview: {
    label: "أوقات صلاة توضيحية وآية من القرآن الكريم",
    today: "منتظِر",
    verseLabel: "آية من القرآن الكريم",
    verse: "فَإِنَّ مَعَ الْعُسْرِ يُسْرًا",
    reference: "الشرح · ٩٤:٥",
    prayers: ["الفجر", "الظهر", "المغرب"],
    times: ["٠٤:٤٢", "١٢:٠٨", "١٧:٣٦"],
    example: "أوقات توضيحية، وليست مواقيت صلاة فعلية.",
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
  companions:
    "بالعربية والإنجليزية. لأجهزة \u2066iPhone\u2069 و\u2066iPad\u2069، مع تطبيق مرافق لساعة \u2066Apple Watch\u2069 وأدوات للشاشة الرئيسية.",
  faq: {
    title: "تفاصيل مفيدة",
    items: [
      {
        q: "هل يمكنني ضبط مواقيت الصلاة والتاريخ الهجري؟",
        a: "يمكنك اختيار طريقة حساب الصلاة وضبط بدايات الأشهر الهجرية بما يوافق التواريخ التي تتّبعها.",
      },
      {
        q: "كيف تعمل تنبيهات الصلاة؟",
        a: "فعّل إذن الإشعارات على جهازك، وافتح التطبيق بانتظام ليتمكّن iOS من تحديث جدول التنبيهات القادمة.",
      },
      {
        q: "أين يمكنني تحميل منتظِر؟",
        a: "ستتاح صفحة App Store المرتبطة أعلاه عند إطلاق التطبيق. لا يتوفّر حاليًا تطبيق لأندرويد أو للمتصفح.",
      },
    ],
  },
  footer: {
    top: "العودة إلى الأعلى",
    trademark:
      "Apple وiPhone وiPad وApple Watch علامات تجارية لشركة Apple Inc. وApp Store علامة خدمة لشركة Apple Inc.",
  },
}

export const translations: Record<Locale, typeof en> = { ar, en }

import type { Locale } from "./site"

const en = {
  name: "Muntathir",
  title: "Muntathir: Prayer, Quran, Hadith, and Hijri calendar",
  description:
    "Prayer reminders, Quran and Hadith reading, highlights, Islamic figures, the Hijri calendar, and Qibla. In 15 languages for iPhone, iPad, and Apple Watch.",
  skip: "Skip to content",
  nav: { language: "Choose language" },
  hero: {
    first: "Prayer and",
    second: "daily remembrance.",
    eyebrow: "Prayer · Quran · Hijri calendar",
    text: "Prayer times and daily verses, Quran and Hadith reading, and the dates that matter. Keep your daily remembrance together in Muntathir.",
    cta: "Download Muntathir from the App Store",
  },
  features: {
    title: "In the app",
    items: [
      {
        title: "Prayer times",
        text: "Choose a calculation method and set prayer reminders for your location.",
      },
      {
        title: "Quran reader",
        text: "Read and search the Quran with translations, and return to your reading position.",
      },
      {
        title: "Hadith library",
        text: "Download collections to browse chapters and search Arabic and English offline.",
      },
      {
        title: "Highlights and notes",
        text: "Highlight Quran and Hadith passages, add notes, and share text or image cards.",
      },
      {
        title: "Islamic figures",
        text: "Explore religious figures, their family relationships, and related observances.",
      },
      { title: "Daily Quran verse", text: "Read a verse each day and share it as a card." },
      {
        title: "Hijri calendar",
        text: "Follow Islamic dates and observances, with adjustable month starts.",
      },
      {
        title: "Qibla",
        text: "Find Qibla on a map, with alignment guidance and haptic feedback on supported devices.",
      },
    ],
  },
  calendar: {
    title: "Islamic calendar subscription",
    subscribe: "Subscribe to calendar",
    browse: "Browse events",
    description: "Not all dates are verified",
  },
  companions:
    "Available in 15 languages, including Arabic and English. Made for iPhone and iPad, with an Apple Watch companion and Home Screen widgets.",
  faq: {
    title: "A few useful details",
    items: [
      {
        q: "Can I read offline?",
        a: "Quran Arabic and English are bundled. Download other Quran translations and the Hadith library in Settings → Downloads, then read them offline.",
      },
      {
        q: "Can I keep highlights and notes?",
        a: "Highlight Quran and Hadith passages and attach notes. Personal highlights sync through your private iCloud account when enabled.",
      },
      {
        q: "Can I adjust prayer times?",
        a: "You can choose the prayer calculation method in the app’s settings.",
      },
      {
        q: "Which calendar verification methods are supported?",
        a: "Choose the system calendar, local naked-eye sighting for the Middle East, or government announcements from Saudi Arabia. Adjust individual months by up to two days.",
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
  title: "منتظِر — الصلاة والقرآن والحديث والتقويم الهجري",
  description:
    "تنبيهات الصلاة وقراءة القرآن والحديث والتظليلات والأعلام والتقويم الهجري والقبلة. بـ١٥ لغة لأجهزة iPhone وiPad وApple Watch.",
  skip: "انتقل إلى المحتوى",
  nav: { language: "اختر اللغة" },
  hero: {
    first: "صلاتك،",
    second: "وذكرُك اليومي.",
    eyebrow: "الصلاة · القرآن · التقويم الهجري",
    text: "مواقيت الصلاة وآيات يومية، وقراءة القرآن والحديث، والمناسبات التي تهمّك. اجمع عبادتك وذكرَك اليومي في منتظِر.",
    cta: "تحميل تطبيق مُنتظِر من متجر التطبيقات",
  },
  features: {
    title: "في التطبيق",
    items: [
      { title: "مواقيت الصلاة", text: "اختر طريقة الحساب واضبط تنبيهات الصلاة حسب موقعك." },
      {
        title: "قراءة القرآن",
        text: "اقرأ القرآن وابحث في آياته مع الترجمات، وعُد إلى موضع قراءتك.",
      },
      {
        title: "مكتبة الحديث",
        text: "نزّل الكتب لتصفّح الأبواب والبحث بالعربية والإنجليزية دون اتصال.",
      },
      {
        title: "التظليلات والملاحظات",
        text: "ظلّل مقاطع من القرآن والحديث وأضف ملاحظات وشارك النصوص أو البطاقات المصوّرة.",
      },
      { title: "الأعلام", text: "تعرّف إلى الأعلام والعلاقات العائلية بينهم والمناسبات المرتبطة بهم." },
      { title: "آية كل يوم", text: "اقرأ آية قرآنية يوميًا وشاركها في بطاقة." },
      {
        title: "التقويم الهجري",
        text: "تابع التواريخ والمناسبات الإسلامية، مع إمكانية ضبط بدايات الأشهر.",
      },
      {
        title: "اتجاه القبلة",
        text: "اعرف اتجاه القبلة على الخريطة، مع إرشادات للمحاذاة وتنبيهات لمسية على الأجهزة المدعومة.",
      },
    ],
  },
  calendar: {
    title: "الاشتراك في تقويم المناسبات الإسلامية",
    subscribe: "اشترك في التقويم",
    browse: "تصفّح المناسبات",
    description: "ليست كل التواريخ مؤكدة",
  },
  companions:
    "متوفر بـ١٥ لغة، منها العربية والإنجليزية. لأجهزة \u2066iPhone\u2069 و\u2066iPad\u2069، مع تطبيق مرافق لساعة \u2066Apple Watch\u2069 وأدوات للشاشة الرئيسية.",
  faq: {
    title: "تفاصيل مفيدة",
    items: [
      {
        q: "هل يمكنني القراءة دون اتصال؟",
        a: "النص القرآني العربي والترجمة الإنجليزية مضمّنان. نزّل ترجمات القرآن الأخرى ومكتبة الحديث من الإعدادات ← التنزيلات، ثم اقرأها دون اتصال.",
      },
      {
        q: "هل يمكنني حفظ التظليلات والملاحظات؟",
        a: "ظلّل مقاطع من القرآن والحديث وأضف إليها ملاحظات. تتزامن تظليلاتك الشخصية عبر حساب iCloud الخاص بك عند تفعيله.",
      },
      {
        q: "هل يمكنني ضبط مواقيت الصلاة؟",
        a: "يمكنك اختيار طريقة حساب مواقيت الصلاة من إعدادات التطبيق.",
      },
      {
        q: "ما طرق التحقق من بداية الشهر المدعومة؟",
        a: "يمكنك اختيار تقويم النظام، أو الرؤية بالعين المجردة لمنطقة الشرق الأوسط، أو الإعلانات الرسمية للسعودية. ويمكنك تعديل كل شهر بما يصل إلى يومين.",
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

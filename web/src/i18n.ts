import type { Locale } from "./site"

const en = {
  name: "Muntathir",
  title: "Muntathir: Prayer, Quran, Hadith, and Hijri calendar",
  description:
    "Prayer times, Quran and Hadith, supplications, tasbih, rakaat tools, personal highlights, and the Hijri calendar. In 15 languages for iPhone, iPad, and Apple Watch.",
  skip: "Skip to content",
  nav: { language: "Choose language" },
  hero: {
    first: "Prayer and",
    second: "daily remembrance.",
    eyebrow: "Prayer · Quran · Hijri calendar",
    text: "From the first prayer to a quiet moment with the Quran: reading, supplications, tasbih, and the dates that matter. Keep your daily worship together in Muntathir.",
    cta: "Download Muntathir from the App Store",
  },
  features: {
    title: "In the app",
    items: [
      {
        title: "Read and reflect",
        text: "Read the Quran verse by verse or in Mushaf pages, choose translations, and return to your reading position. A daily ayah offers a moment to pause and share.",
      },
      {
        title: "Build your reading library",
        text: "Choose which Hadith books to keep, explore supplications and rulings, and read downloaded content offline. Search online, with on-device search when the service is unavailable.",
      },
      {
        title: "Keep what matters",
        text: "Bookmark passages, highlight selected Quran and Hadith text, add personal notes, and share text or image cards. Highlights and notes sync through your private iCloud account when available.",
      },
      {
        title: "Make time for prayer",
        text: "See local prayer times, choose your calculation method, and set reminders. Watch the Today sky change throughout the day, with weather and upcoming observances close at hand.",
      },
      {
        title: "Tools for daily remembrance",
        text: "Count with interactive 3D tasbih beads. Use front-camera assistance to track rakaat, and find Qibla with a map, alignment guidance, and haptic feedback on supported devices.",
      },
      {
        title: "See your activity",
        text: "Review your recorded prayers, reading, and remembrance in one place. Return to your daily practice at your own pace.",
      },
      {
        title: "Follow dates and discover people",
        text: "Browse the Hijri calendar and Islamic observances, adjust month starts, and explore Islamic figures and their family relationships.",
      },
      {
        title: "At home on your devices",
        text: "Use Muntathir on iPhone and iPad, check prayer times on Apple Watch, and keep dates and prayers nearby with Home Screen widgets.",
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
        a: "Quran Arabic and English are bundled. Download other Quran translations, the Hadith books you want to keep, supplications, and rulings before reading them offline. Smart search needs an internet connection.",
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
    "مواقيت الصلاة والقرآن والحديث والأدعية والتسبيح وأدوات الركعات والتظليلات والتقويم الهجري. بـ١٥ لغة لأجهزة iPhone وiPad وApple Watch.",
  skip: "انتقل إلى المحتوى",
  nav: { language: "اختر اللغة" },
  hero: {
    first: "صلاتك،",
    second: "وذكرُك اليومي.",
    eyebrow: "الصلاة · القرآن · التقويم الهجري",
    text: "من أول صلاة إلى لحظة هادئة مع القرآن: قراءة وأدعية وتسبيح، ومناسبات تهمّك. اجمع عبادتك وذكرَك اليومي في منتظِر.",
    cta: "تحميل تطبيق مُنتظِر من متجر التطبيقات",
  },
  features: {
    title: "في التطبيق",
    items: [
      {
        title: "اقرأ وتدبّر",
        text: "اقرأ القرآن آية بآية أو بصفحات المصحف، واختر الترجمات وعُد إلى موضع قراءتك. وتمنحك آية اليوم لحظة للتأمل والمشاركة.",
      },
      {
        title: "مكتبتك للقراءة",
        text: "اختر كتب الحديث التي تريد الاحتفاظ بها، وتصفّح الأدعية والأحكام، واقرأ المحتوى المنزّل دون اتصال. ابحث عبر الإنترنت، أو على جهازك تلقائيًا عند تعذّر الاتصال بالخدمة.",
      },
      {
        title: "احتفظ بما يهمّك",
        text: "أضف علامات مرجعية، وظلّل مقاطع من القرآن والحديث، ودوّن ملاحظاتك وشارك النصوص أو البطاقات المصوّرة. تتزامن التظليلات والملاحظات عبر حساب iCloud الخاص بك عند توفره.",
      },
      {
        title: "حافظ على وقت الصلاة",
        text: "تابع المواقيت حسب موقعك، واختر طريقة الحساب واضبط التنبيهات. شاهد تغيّر سماء اليوم، واطّلع على الطقس والمناسبات القادمة.",
      },
      {
        title: "أدوات لذكرك اليومي",
        text: "سبّح بخرزات ثلاثية الأبعاد، واستعن بالكاميرا الأمامية لعدّ الركعات. واعرف اتجاه القبلة على الخريطة، مع إرشادات المحاذاة والتنبيهات اللمسية على الأجهزة المدعومة.",
      },
      {
        title: "راجع نشاطك",
        text: "تابع صلواتك المسجّلة وقراءتك وذكرك في مكان واحد، وعُد إلى عبادتك اليومية على وتيرتك.",
      },
      {
        title: "تواريخ وأعلام",
        text: "تصفّح التقويم الهجري والمناسبات الإسلامية واضبط بدايات الأشهر. وتعرّف إلى الأعلام والعلاقات العائلية بينهم.",
      },
      {
        title: "معك على أجهزتك",
        text: "استخدم منتظِر على iPhone وiPad، وتابع الصلاة على Apple Watch، وأبقِ التواريخ والمواقيت قريبة بأدوات الشاشة الرئيسية.",
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
        a: "النص القرآني العربي والترجمة الإنجليزية مضمّنان. نزّل ترجمات القرآن الأخرى وكتب الحديث والأدعية والأحكام قبل قراءتها دون اتصال. يحتاج البحث الذكي إلى اتصال بالإنترنت.",
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

import type { Timing } from './calendar.ts'
import { civil, type Day, type HijriDate } from './day.ts'
import type { Method, TimeName } from './prayer.ts'
import type { SearchProblem, Text } from './types.ts'

export type Locale = 'ar' | 'en'

// Wording follows apple/Muntathir/Localizable.xcstrings wherever the apps have the string.
const en = {
  name: 'Muntathir',
  intro:
    'Prayer times, Qibla, the Hijri calendar, the daily ayah, and a library of Quran, Hadith, supplications and rulings.',
  helpText:
    'Share your location for prayer times and Qibla, or send any words to search the Quran and Hadith.\n\n/prayers Prayer times\n/qibla Qibla\n/today Date, event and ayah\n/verse Daily ayah\n/search Search\n/rulings Search rulings\n/language Language\n/privacy Privacy\n\nYour location is used for the reply and never stored by Muntathir.',
  open: 'Open Muntathir',
  shareLocation: 'Share location',
  askLocation:
    'Share your location to see its prayer times and Qibla. It is used for the reply and not stored.\n\nOn a computer, open the app to enter coordinates.',
  prayers: 'Prayer times',
  prayersUnavailable: 'Prayer times unavailable for this location and date.',
  qibla: 'Qibla',
  fromNorth: 'from true north',
  today: 'Today',
  tonight: 'Tonight',
  tomorrow: 'Tomorrow',
  calendar: 'Calendar',
  events: 'Events',
  nextEvent: 'Next event',
  noEvents: 'No events',
  expected: 'Expected',
  datesNote: 'Not all dates are verified',
  ah: 'AH',
  riyadhNote: 'Date in Riyadh. Share your location for your own date.',
  dailyAyah: 'Daily ayah',
  share: 'Share',
  source: 'Source',
  library: 'Library',
  quran: 'Holy Quran',
  hadith: 'Hadith',
  four: 'The Four',
  six: 'The Six',
  other: 'Other',
  supplications: 'Supplications',
  rulings: 'Rulings',
  quranHadith: 'Quran + Hadith',
  search: 'Search',
  searchPrompt: 'Send the words to search for, for example: patience in hardship',
  searchUsage: 'Add the words after the command, for example: /rulings fasting while traveling',
  searchExpired: 'That search is no longer available. Send the words again.',
  searching: 'Searching…',
  noResults: 'No results',
  authority: 'Authority',
  allAuthorities: 'All authorities',
  allLanguages: 'All languages',
  back: 'Back',
  continues: 'The text continues in the app.',
  openFull: 'Read in full',
  notFound: 'This text is no longer available.',
  rulingsNotice: 'This app is not a source of religious rulings. Refer to official sources.',
  officialSource: 'Official source',
  footnotes: 'Footnotes',
  translation: 'Translation',
  privacy: 'Privacy policy',
  chooseLanguage: 'Choose the language for replies in this chat.',
  telegramLanguage: 'Use my Telegram language',
  languageSaved: 'Language saved.',
  failed: 'Something went wrong. Try again.',
  // Mini App
  retry: 'Try again',
  reopen: 'Open the app again from the bot.',
  outside: 'Open Muntathir from Telegram.',
  loading: 'Loading…',
  location: 'Location',
  useLocation: 'Use my location',
  changeLocation: 'Change location',
  locationDenied: 'Location is unavailable. Allow it in settings or enter coordinates.',
  openSettings: 'Open settings',
  locationPrivate: 'Your location stays on this device.',
  manual: 'Enter coordinates',
  latitude: 'Latitude',
  longitude: 'Longitude',
  timeZone: 'Time zone',
  save: 'Save',
  invalidLocation: 'Enter a valid latitude, longitude and time zone.',
  method: 'Method',
  language: 'Language',
  settings: 'Settings',
  remove: 'Remove location',
  next: 'Next',
  previous: 'Previous',
  more: 'Load more',
  compassStart: 'Use compass',
  compassUnavailable: 'Compass unavailable. Use the bearing from true north.',
  compassHint: 'Hold the phone flat, away from metal and magnets.',
  aligned: 'Facing the Qibla',
  turnLeft: 'Turn left',
  turnRight: 'Turn right',
  introduction: 'Introduction',
  gradings: 'Gradings',
  previousMonth: 'Previous month',
  nextMonth: 'Next month',
  verses: 'verses',
  continueReading: 'Continue reading',
}

const ar: Record<keyof typeof en, string> = {
  name: 'منتظِر',
  intro:
    'أوقات الصلاة والقبلة والتقويم الهجري وآية اليوم، ومكتبة للقرآن والحديث والأدعية والأحكام.',
  helpText:
    'شارك موقعك لمعرفة أوقات الصلاة والقبلة، أو أرسل أي كلمات للبحث في القرآن والحديث.\n\n/prayers أوقات الصلاة\n/qibla القبلة\n/today التاريخ والمناسبة والآية\n/verse آية اليوم\n/search البحث\n/rulings البحث في الأحكام\n/language اللغة\n/privacy الخصوصية\n\nيُستخدم موقعك للرد فقط، ولا يحفظه منتظِر.',
  open: 'افتح منتظِر',
  shareLocation: 'مشاركة الموقع',
  askLocation:
    'شارك موقعك لمعرفة أوقات الصلاة فيه واتجاه القبلة. يُستخدم للرد ولا يُحفظ.\n\nعلى الحاسوب، افتح التطبيق لإدخال الإحداثيات.',
  prayers: 'أوقات الصلاة',
  prayersUnavailable: 'أوقات الصلاة غير متاحة لهذا الموقع والتاريخ',
  qibla: 'القبلة',
  fromNorth: 'من الشمال الحقيقي',
  today: 'اليوم',
  tonight: 'الليلة',
  tomorrow: 'غدًا',
  calendar: 'التقويم',
  events: 'المناسبات',
  nextEvent: 'المناسبة القادمة',
  noEvents: 'لا توجد مناسبات',
  expected: 'متوقّع',
  datesNote: 'ليست كل التواريخ مؤكدة',
  ah: 'هـ',
  riyadhNote: 'التاريخ في الرياض. شارك موقعك لمعرفة التاريخ لديك.',
  dailyAyah: 'آية اليوم',
  share: 'مشاركة',
  source: 'المصدر',
  library: 'المكتبة',
  quran: 'القرآن الكريم',
  hadith: 'الحديث',
  four: 'الأربعة',
  six: 'الستة',
  other: 'أخرى',
  supplications: 'الأدعية',
  rulings: 'الأحكام',
  quranHadith: 'القرآن والحديث',
  search: 'البحث',
  searchPrompt: 'أرسل كلمات البحث، مثلًا: الصبر عند البلاء',
  searchUsage: 'أضف الكلمات بعد الأمر، مثلًا: /rulings صوم المسافر',
  searchExpired: 'لم يعد هذا البحث متاحًا. أرسل الكلمات مجددًا.',
  searching: 'جارٍ البحث…',
  noResults: 'لا توجد نتائج',
  authority: 'المرجع',
  allAuthorities: 'كل المراجع',
  allLanguages: 'كل اللغات',
  back: 'رجوع',
  continues: 'تتمة النص في التطبيق.',
  openFull: 'اقرأ النص كاملًا',
  notFound: 'لم يعد هذا النص متاحًا.',
  rulingsNotice: 'لا يُعتبر هذا التطبيق مصدرًا للأحكام الشرعية. يجب الرجوع للمصادر الرسمية',
  officialSource: 'المصدر الرسمي',
  footnotes: 'الهوامش',
  translation: 'الترجمة',
  privacy: 'سياسة الخصوصية',
  chooseLanguage: 'اختر لغة الردود في هذه المحادثة.',
  telegramLanguage: 'استخدام لغة تيليجرام',
  languageSaved: 'تم حفظ اللغة.',
  failed: 'حدث خطأ. حاول مجددًا.',
  retry: 'حاول مجددًا',
  reopen: 'افتح التطبيق مجددًا من البوت.',
  outside: 'افتح منتظِر من تيليجرام.',
  loading: 'جارٍ التحميل…',
  location: 'الموقع',
  useLocation: 'استخدام موقعي',
  changeLocation: 'تغيير الموقع',
  locationDenied: 'الموقع غير متاح. اسمح به في الإعدادات أو أدخل الإحداثيات.',
  openSettings: 'فتح الإعدادات',
  locationPrivate: 'يبقى موقعك على هذا الجهاز.',
  manual: 'إدخال الإحداثيات',
  latitude: 'خط العرض',
  longitude: 'خط الطول',
  timeZone: 'المنطقة الزمنية',
  save: 'حفظ',
  invalidLocation: 'أدخل خط عرض وخط طول ومنطقة زمنية صحيحة.',
  method: 'الطريقة',
  language: 'اللغة',
  settings: 'الإعدادات',
  remove: 'إزالة الموقع',
  next: 'التالي',
  previous: 'السابق',
  more: 'عرض المزيد',
  compassStart: 'استخدام البوصلة',
  compassUnavailable: 'البوصلة غير متاحة. استخدم الزاوية من الشمال الحقيقي.',
  compassHint: 'أمسك الهاتف أفقيًا بعيدًا عن المعادن والمغناطيس.',
  aligned: 'باتجاه القبلة',
  turnLeft: 'اتجه يسارًا',
  turnRight: 'اتجه يمينًا',
  introduction: 'المقدمة',
  gradings: 'درجات الحديث',
  previousMonth: 'الشهر السابق',
  nextMonth: 'الشهر التالي',
  verses: 'آية',
  continueReading: 'متابعة القراءة',
}

export const strings: Record<Locale, typeof en> = { en, ar }

export const TIME_NAMES: Record<Locale, Record<TimeName, string>> = {
  en: {
    imsak: 'Imsak',
    fajr: 'Fajr',
    sunrise: 'Sunrise',
    dhuhr: 'Dhuhr',
    asr: 'Asr',
    sunset: 'Sunset',
    maghrib: 'Maghrib',
    isha: 'Isha',
    midnight: 'Midnight',
  },
  ar: {
    imsak: 'الإمساك',
    fajr: 'الفجر',
    sunrise: 'الشروق',
    dhuhr: 'الظهر',
    asr: 'العصر',
    sunset: 'الغروب',
    maghrib: 'المغرب',
    isha: 'العشاء',
    midnight: 'منتصف الليل',
  },
}

export const METHOD_NAMES: Record<Locale, Record<Method, string>> = {
  en: { tehran: 'Jafari, Tehran', jafari: 'Jafari, Qum', ummAlQura: 'Umm al-Qura' },
  ar: { tehran: 'جعفري - طهران', jafari: 'جعفري - قُم', ummAlQura: 'أم القرى' },
}

// Fixed here because WebView ICU varies.
const MONTHS: Record<Locale, string[]> = {
  en: ['Muharram', 'Safar', 'Rabiʻ I', 'Rabiʻ II', 'Jumada I', 'Jumada II', 'Rajab', 'Shaʻban', 'Ramadan', 'Shawwal', 'Dhuʻl-Qiʻdah', 'Dhuʻl-Hijjah'],
  ar: ['محرم', 'صفر', 'ربيع الأول', 'ربيع الآخر', 'جمادى الأولى', 'جمادى الآخرة', 'رجب', 'شعبان', 'رمضان', 'شوال', 'ذو القعدة', 'ذو الحجة'],
}

export const PROBLEMS: Record<Locale, Record<SearchProblem, string>> = {
  en: {
    empty: 'Enter words to search for.',
    long: 'The search is too long. Use up to 512 characters.',
    invalid: 'That search or reference is not valid.',
    limited: 'Too many searches. Try again later.',
    unavailable: 'Search is unavailable right now. The library still works in the app.',
  },
  ar: {
    empty: 'أدخل كلمات للبحث.',
    long: 'نص البحث طويل. استخدم 512 حرفًا كحد أقصى.',
    invalid: 'البحث أو المرجع غير صحيح.',
    limited: 'عمليات بحث كثيرة. حاول لاحقًا.',
    unavailable: 'البحث غير متاح حاليًا. ما زالت المكتبة متاحة في التطبيق.',
  },
}

export function localeOf(code: string | undefined): Locale {
  return code?.toLowerCase().startsWith('ar') ? 'ar' : 'en'
}

export function pick(value: Text, locale: Locale): string {
  return value[locale] || value.ar || value.en
}

const tag = (locale: Locale) => `${locale}-u-ca-gregory-nu-latn`

export function monthTitle(month: number, locale: Locale): string {
  return MONTHS[locale][month - 1]!
}

export function formatHijri(date: HijriDate, locale: Locale): string {
  return `${date.date} ${monthTitle(date.month, locale)} ${date.year} ${strings[locale].ah}`
}

export function formatDay(value: Day, locale: Locale, style: 'long' | 'short' = 'long'): string {
  const { year, month, date } = civil(value)
  return new Intl.DateTimeFormat(tag(locale), {
    timeZone: 'UTC',
    weekday: style,
    day: 'numeric',
    month: style,
    ...(style === 'long' ? { year: 'numeric' as const } : {}),
  }).format(Date.UTC(year, month - 1, date))
}

export function formatTime(instant: number, zone: string, locale: Locale): string {
  return new Intl.DateTimeFormat(tag(locale), {
    timeZone: zone,
    hour: 'numeric',
    minute: '2-digit',
  }).format(instant)
}

export function formatTiming(timing: Timing, locale: Locale): string {
  if (typeof timing === 'string') return strings[locale][timing]
  return new Intl.RelativeTimeFormat(`${locale}-u-nu-latn`, { numeric: 'always' }).format(timing.days, 'day')
}

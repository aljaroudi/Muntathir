package com.aljaroudi.muntathir.widgets

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProviderInfo
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.util.TypedValue
import android.widget.RemoteViews
import androidx.annotation.DrawableRes
import androidx.annotation.LayoutRes
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceModifier
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.appwidget.AndroidRemoteViews
import androidx.glance.appwidget.LocalAppWidgetOptions
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.padding
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.app.AppModel
import com.aljaroudi.muntathir.data.QuranDatabase
import com.aljaroudi.muntathir.data.QuranTranslations
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.android.EntryPointAccessors
import dagger.hilt.components.SingletonComponent
import java.time.Clock
import java.time.Instant
import java.util.Locale

/** What widgets, their receivers and the tile read; they live outside Hilt's injected Android classes. */
@EntryPoint
@InstallIn(SingletonComponent::class)
interface WidgetEntryPoint {
    fun model(): AppModel

    fun quran(): QuranDatabase

    fun translations(): QuranTranslations

    fun clock(): Clock

    fun updater(): WidgetUpdater
}

fun Context.widgetDeps(): WidgetEntryPoint =
    EntryPointAccessors.fromApplication(applicationContext, WidgetEntryPoint::class.java)

private val WIDGET_PADDING = 14.dp

/** The language widget strings resolve in (the per-app language on Android 13+). */
val Context.widgetLocale: Locale get() = resources.configuration.locales[0]

/** Text styles of widget text; each layout sets the font and a color that follows dark mode. */
enum class WidgetFont(
    @param:LayoutRes val layout: Int,
) {
    Body(R.layout.widget_text),
    Strong(R.layout.widget_text_strong),
    StrongCentered(R.layout.widget_text_strong_centered),
    Secondary(R.layout.widget_text_secondary),
    Centered(R.layout.widget_text_centered),
    Quran(R.layout.widget_text_quran),
}

/** Widget text in the app font (or Hafs), which Glance's own `Text` can't use. */
@Composable
fun WidgetText(
    text: String,
    sizeSp: Float,
    modifier: GlanceModifier = GlanceModifier,
    font: WidgetFont = WidgetFont.Body,
    maxLines: Int = 1,
) {
    val views =
        RemoteViews(LocalContext.current.packageName, font.layout).apply {
            setTextViewText(R.id.widget_text, text)
            setTextViewTextSize(R.id.widget_text, TypedValue.COMPLEX_UNIT_SP, sizeSp)
            setInt(R.id.widget_text, "setMaxLines", maxLines)
        }
    AndroidRemoteViews(views, modifier)
}

/** A countdown to [target] that the launcher ticks by itself. */
@Composable
fun WidgetCountdown(
    target: Instant,
    now: Instant,
    modifier: GlanceModifier = GlanceModifier,
) {
    val views =
        RemoteViews(LocalContext.current.packageName, R.layout.widget_countdown).apply {
            val base = SystemClock.elapsedRealtime() + (target.toEpochMilli() - now.toEpochMilli())
            setChronometer(R.id.widget_countdown, base, null, true)
            setChronometerCountDown(R.id.widget_countdown, true)
        }
    AndroidRemoteViews(views, modifier)
}

/** Whether the lock screen hosts this widget: Android's hub binds widgets with the keyguard category. */
@Composable
fun isOnLockScreen(): Boolean {
    val host = LocalAppWidgetOptions.current.getInt(AppWidgetManager.OPTION_APPWIDGET_HOST_CATEGORY)
    return (host and AppWidgetProviderInfo.WIDGET_CATEGORY_KEYGUARD) != 0
}

/** Swift's accessory families: a centered column on the plain surface, which stays legible on any wallpaper. */
@Composable
fun LockScreenSurface(
    open: Intent,
    content: @Composable () -> Unit,
) {
    WidgetSurface(R.drawable.widget_background, open, Alignment.Center) {
        Column(GlanceModifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) { content() }
    }
}

/**
 * The height a lock screen card has for text, in sp. RemoteViews can't measure, so layouts choose their lines
 * and sizes from this where Swift uses `ViewThatFits`.
 */
@Composable
fun lockScreenTextRoom(): Float =
    (LocalSize.current.height - WIDGET_PADDING * 2).value / LocalContext.current.resources.configuration.fontScale

/** The widget container: [background] with launcher corners, opening [open] when tapped. */
@Composable
fun WidgetSurface(
    @DrawableRes background: Int,
    open: Intent,
    contentAlignment: Alignment = Alignment.TopStart,
    content: @Composable () -> Unit,
) {
    Box(
        GlanceModifier
            .fillMaxSize()
            .appWidgetBackground()
            .background(ImageProvider(background))
            .cornerRadius(R.dimen.widget_radius)
            .clickable(actionStartActivity(open))
            .padding(WIDGET_PADDING),
        contentAlignment = contentAlignment,
    ) { content() }
}

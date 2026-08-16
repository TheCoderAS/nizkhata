package com.nizkhata.nizkhata

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

// "Dues at a glance" home-screen widget. Data is pushed from Flutter via the
// home_widget plugin (WidgetSync); tapping opens the app on the Dues screen
// through the verified App Link.
class DuesWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.dues_widget)
            views.setTextViewText(
                R.id.widget_receivable,
                "In: " + (widgetData.getString("receivable", null) ?: "—")
            )
            views.setTextViewText(
                R.id.widget_payable,
                "Out: " + (widgetData.getString("payable", null) ?: "—")
            )
            views.setTextViewText(
                R.id.widget_next,
                widgetData.getString("next_due", null) ?: "Open NizKhata to sync"
            )
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://nizkhata.web.app/dues"))
                .setPackage(context.packageName)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            val pending = PendingIntent.getActivity(
                context, 0, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root, pending)
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}

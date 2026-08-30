package com.nizkhata.nizkhata

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

// "Dues at a glance" home-screen widget: totals header + a scrollable list of
// ALL unsettled dues (RemoteViewsService). Data is pushed from Flutter via the
// home_widget plugin (WidgetSync); tapping anywhere opens the app on Dues
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
                "In " + (widgetData.getString("receivable", null) ?: "—")
            )
            views.setTextViewText(
                R.id.widget_payable,
                "Out " + (widgetData.getString("payable", null) ?: "—")
            )

            // Scrollable dues list backed by the RemoteViewsService below.
            val svc = Intent(context, DuesWidgetService::class.java)
            svc.data = Uri.parse("nizkhata://widget/dues/$widgetId")
            views.setRemoteAdapter(R.id.widget_list, svc)
            views.setEmptyView(R.id.widget_list, R.id.widget_empty)

            val open = Intent(Intent.ACTION_VIEW, Uri.parse("https://nizkhata.web.app/dues"))
                .setPackage(context.packageName)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            val openPending = PendingIntent.getActivity(
                context, 0, open,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root, openPending)
            // List rows share the same open-app intent via a template.
            views.setPendingIntentTemplate(R.id.widget_list, openPending)

            appWidgetManager.updateAppWidget(widgetId, views)
        }
        // Re-read the pushed JSON whenever Flutter asks for an update.
        appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetIds, R.id.widget_list)
    }
}

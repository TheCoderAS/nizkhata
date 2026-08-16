package com.nizkhata.nizkhata

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray

// Backs the widget's scrollable ListView with the dues JSON pushed from
// Flutter (home_widget prefs, key "dues_json"):
// [{"t": title, "d": date label, "a": amount label, "r": receivable bool}, …]
class DuesWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        DuesFactory(applicationContext)
}

class DuesFactory(private val context: Context) : RemoteViewsService.RemoteViewsFactory {
    private var items = JSONArray()

    override fun onCreate() {}

    override fun onDataSetChanged() {
        items = try {
            JSONArray(HomeWidgetPlugin.getData(context).getString("dues_json", "[]") ?: "[]")
        } catch (_: Exception) {
            JSONArray()
        }
    }

    override fun onDestroy() {}

    override fun getCount(): Int = items.length()

    override fun getViewAt(position: Int): RemoteViews {
        val row = RemoteViews(context.packageName, R.layout.dues_widget_item)
        try {
            val o = items.getJSONObject(position)
            row.setTextViewText(R.id.item_title, o.optString("t", "Due"))
            row.setTextViewText(R.id.item_date, o.optString("d", ""))
            row.setTextViewText(R.id.item_amount, o.optString("a", ""))
            row.setTextColor(
                R.id.item_amount,
                if (o.optBoolean("r", false)) Color.parseColor("#34D399")
                else Color.parseColor("#F87171")
            )
        } catch (_: Exception) {
        }
        // Fill-in for the provider's pending-intent template (opens the app).
        row.setOnClickFillInIntent(R.id.item_root, Intent())
        return row
    }

    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount(): Int = 1
    override fun getItemId(position: Int): Long = position.toLong()
    override fun hasStableIds(): Boolean = true
}

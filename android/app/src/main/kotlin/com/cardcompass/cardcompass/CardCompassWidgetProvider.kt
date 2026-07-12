package com.cardcompass.cardcompass

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class CardCompassWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.widget_layout).apply {

                val cardName = widgetData.getString("widget_card_name", "No cards available")
                val reasoning = widgetData.getString("widget_reasoning", "Open app to configure")

                setTextViewText(R.id.widget_card_name, cardName)
                setTextViewText(R.id.widget_reasoning, reasoning)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}

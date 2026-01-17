#!/usr/bin/env python3
import logging
logging.basicConfig(level=logging.INFO)
logging.info("✅ telegram_webapp_bot starting…")
import os
import asyncio
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler, ContextTypes

BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "").strip()
DASHBOARD_URL = os.getenv("DASHBOARD_URL", "https://8x8org.youware.app").strip()

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not BOT_TOKEN:
        await update.message.reply_text("Bot token missing. Set TELEGRAM_BOT_TOKEN.")
        return

    kb = [
        [InlineKeyboardButton("🚀 Open Dashboard", web_app=WebAppInfo(url=DASHBOARD_URL))],
        [InlineKeyboardButton("🔗 Open in Browser", url=DASHBOARD_URL)],
    ]
    await update.message.reply_text(
        "Welcome to 8x8org.\nOpen the dashboard as a Telegram WebApp:",
        reply_markup=InlineKeyboardMarkup(kb),
    )

async def health(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text("ok")

def main():
    if not BOT_TOKEN:
        raise SystemExit("TELEGRAM_BOT_TOKEN not set")
    app = Application.builder().token(BOT_TOKEN).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("health", health))
    app.run_polling(close_loop=False)

if __name__ == "__main__":
    main()

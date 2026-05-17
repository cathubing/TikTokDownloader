#!/bin/bash
set -e

echo "[start.sh] 开始初始化..."

PORT="${PORT:-5555}"

# 从 Supabase 读取最新 Cookie，失败时使用环境变量兜底
echo "[start.sh] 从 Supabase 读取 Cookie..."

COOKIE=$(python3 - <<'PYEOF'
import os, sys
try:
    from supabase import create_client
    url = os.environ.get("SUPABASE_URL", "")
    key = os.environ.get("SUPABASE_KEY", "")
    if not url or not key:
        raise ValueError("Supabase 环境变量未设置")
    client = create_client(url, key)
    result = (
        client.table("cookies")
        .select("value")
        .eq("key", "douyin")
        .order("updated_at", desc=True)
        .limit(1)
        .execute()
    )
    if result.data:
        print(result.data[0]["value"])
    else:
        raise ValueError("Supabase 中无 Cookie 数据")
except Exception as e:
    print(f"[start.sh] Supabase 读取失败: {e}，使用环境变量兜底", file=sys.stderr)
    print(os.environ.get("DOUYIN_COOKIE", ""))
PYEOF
)

# 确保 Volume 目录存在
mkdir -p /app/Volume

# 生成 settings.json
echo "[start.sh] 生成配置文件..."

python3 - <<PYEOF
import json, sys, os

cookie_value = """${COOKIE}"""

config = {
    "accounts_urls": [],
    "accounts_urls_tiktok": [],
    "mix_urls": [],
    "mix_urls_tiktok": [],
    "owner_url": {},
    "root": "",
    "folder_name": "Download",
    "name_format": "create_time type nickname desc",
    "date_format": "%Y-%m-%d %H:%M:%S",
    "split": "-",
    "folder_mode": False,
    "music": False,
    "storage_format": "",
    "cookie": cookie_value,
    "cookie_tiktok": "",
    "dynamic_cover": False,
    "static_cover": False,
    "proxy": os.environ.get("PROXY_URL", ""),
    "proxy_tiktok": "",
    "download": True,
    "max_size": 0,
    "chunk": 2097152,
    "timeout": 10,
    "max_retry": 10,
    "max_pages": 0,
    "run_command": "5",
    "ffmpeg": "",
    "douyin_platform": True,
    "tiktok_platform": False
}

try:
    with open("/app/Volume/settings.json", "w", encoding="utf-8") as f:
        json.dump(config, f, ensure_ascii=False, indent=2)
    print("[start.sh] settings.json 生成成功")
except Exception as e:
    print(f"[start.sh] 错误：settings.json 写入失败: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

# 初始化数据库，跳过语言选择和免责声明
echo "[start.sh] 初始化数据库..."
python3 - <<'PYEOF'
import asyncio
import sys
sys.path.insert(0, '/app')
from src.manager import Database

async def init():
    async with Database() as db:
        await db.update_config_data("Disclaimer", 1)
        await db.update_option_data("Language", "zh_CN")
        print("[start.sh] 数据库初始化完成")

asyncio.run(init())
PYEOF

echo "[start.sh] 启动 DouK-Downloader（Web API 模式）..."
exec python3 -c "
import asyncio
import sys
sys.path.insert(0, '/app')

from src.config import Parameter, Settings
from src.custom import PROJECT_ROOT, SERVER_HOST, SERVER_PORT
from src.manager import Database, DownloadRecorder
from src.module import Cookie
from src.record import BaseLogger
from src.tools import ColorfulConsole
from src.application.main_server import APIServer

async def main():
    console = ColorfulConsole()
    settings = Settings(PROJECT_ROOT, console)
    cookie = Cookie(settings, console)
    database = Database()

    async with database:
        recorder = DownloadRecorder(database, True, console)
        logger = BaseLogger
        parameter = Parameter(
            settings,
            cookie,
            logger=logger,
            console=console,
            **settings.read(),
            recorder=recorder,
        )
        parameter.set_headers_cookie()

        server = APIServer(parameter, database)
        await server.run_server(SERVER_HOST, SERVER_PORT)

asyncio.run(main())
"



import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("rtc_screens", HERE.parent / "rtc-test/render_screens.py")
screens = importlib.util.module_from_spec(spec)
spec.loader.exec_module(screens)
screens.HERE = HERE
screens.render("prepare.png", "天气看板", (
    "请在 15 秒内拔掉 USB 线",
    "天气约每 30 分钟自动更新",
    "想看书时，短按电源键后按 Home",
), "横放设备，实体按键位于左侧")

"""Build the portrait instructions, using the shared RTC test screen renderer."""
import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("rtc_screens", HERE.parent / "rtc-test/render_screens.py")
screens = importlib.util.module_from_spec(spec)
spec.loader.exec_module(screens)
screens.HERE = HERE
screens.render("prepare.png", "天气自动刷新测试", (
    "请在 15 秒内拔掉 USB 线",
    "刷新两次，中间休眠 30 秒",
    "完成后自动返回主界面",
), "休眠前可按 Home 退出")

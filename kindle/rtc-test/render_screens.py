"""Rebuild the two native-size instructions; run with the project Pillow venv."""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
FONT = HERE.parents[1] / "assets/fonts/NotoSansSC-VF.ttf"


def render(name, title, lines, footer):
    image = Image.new("L", (1200, 1600), 255)
    draw = ImageDraw.Draw(image)

    def text(y, value, size, weight=500):
        font = ImageFont.truetype(str(FONT), size * 2)
        font.set_variation_by_axes([weight])
        draw.text((600, y * 2), value, font=font, fill=0, anchor="mt")

    text(100, title, 40, 650)
    draw.line((80, 344, 1120, 344), fill=0, width=3)
    for y, line in zip((238, 300, 362), lines):
        text(y, line, 28)
    text(660, footer, 23)
    image = image.resize((600, 800), Image.Resampling.LANCZOS)
    image.point([((value + 8) // 17) * 17 for value in range(256)]).save(HERE / name)


if __name__ == "__main__":
    render("prepare.png", "休眠唤醒测试", (
        "请在 15 秒内拔掉 USB 线",
        "拔线后自动开始测试",
        "约 30 秒后自动返回主界面",
    ), "休眠开始前，按 Home 可取消")
    render("sleep.png", "正在测试休眠", (
        "屏幕保持这张图片属于正常",
        "约 30 秒后自动唤醒",
        "测试结束后返回主界面",
    ), "如果未恢复，请短按电源键唤醒")

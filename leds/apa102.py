"""
APA102 LED driver using libgpiod — works on both RPi5 (Trixie) and Jetson Orin Nano.

Supports both gpiod v1 (1.6.x, Ubuntu 22.04/Jetson) and v2 (2.x, Trixie).

The Pimoroni Blinkt! uses 8 APA102 LEDs driven by a simple clock/data protocol
on two GPIO pins. This driver bit-bangs the protocol using gpiod.

Usage:
    from apa102 import Blinkt

    leds = Blinkt()          # Auto-detects platform
    leds.set_pixel(0, 255, 0, 0, brightness=0.5)
    leds.show()
    leds.clear()
    leds.show()
    leds.cleanup()
"""

import gpiod
import time

# Detect gpiod API version
GPIOD_V2 = hasattr(gpiod, "LineSettings")

# Platform-specific GPIO mappings for the Blinkt! (data + clock pins)
# Blinkt! uses physical pin 16 (data) and pin 18 (clock)
PLATFORM_CONFIG = {
    "rpi5": {
        "chip": "/dev/gpiochip0",  # pinctrl-rp1
        "data_line": 23,           # GPIO23 = physical pin 16
        "clock_line": 24,          # GPIO24 = physical pin 18
    },
    "orin": {
        "chip": "/dev/gpiochip0",  # tegra234-gpio
        "data_line": 126,          # PY.04 = physical pin 16 (SPI1_CS1)
        "clock_line": 125,         # PY.03 = physical pin 18 (SPI1_CS0)
    },
}

NUM_LEDS = 8


def detect_platform():
    """Auto-detect whether we're on RPi5 or Jetson Orin Nano."""
    try:
        with open("/proc/device-tree/model", "r") as f:
            model = f.read().lower()
            if "raspberry" in model:
                return "rpi5"
            if "jetson" in model or "orin" in model:
                return "orin"
    except (FileNotFoundError, PermissionError):
        pass

    # Fallback: check gpiochip label
    try:
        if GPIOD_V2:
            chip = gpiod.Chip("/dev/gpiochip0")
            label = chip.get_info().label
            chip.close()
        else:
            chip = gpiod.Chip("gpiochip0")
            label = chip.label()
            chip.close()

        if "rp1" in label.lower():
            return "rpi5"
        if "tegra" in label.lower():
            return "orin"
    except Exception:
        pass

    raise RuntimeError("Cannot detect platform. Set platform='rpi5' or 'orin' manually.")


class Blinkt:
    """Driver for Pimoroni Blinkt! (8x APA102 LEDs) using libgpiod."""

    def __init__(self, platform=None, brightness=0.2):
        if platform is None:
            platform = detect_platform()

        config = PLATFORM_CONFIG[platform]
        self._data_line_num = config["data_line"]
        self._clock_line_num = config["clock_line"]

        self._pixels = [[0, 0, 0, int(brightness * 31)] for _ in range(NUM_LEDS)]

        if GPIOD_V2:
            self._init_v2(config["chip"])
        else:
            self._init_v1(config["chip"])

    def _init_v2(self, chip_path):
        """Initialize using gpiod v2 API (Trixie, gpiod >= 2.0)."""
        self._api = "v2"
        self._chip = gpiod.Chip(chip_path)
        line_config = {
            (self._data_line_num, self._clock_line_num): gpiod.LineSettings(
                direction=gpiod.line.Direction.OUTPUT,
                output_value=gpiod.line.Value.INACTIVE,
            )
        }
        self._request = self._chip.request_lines(
            consumer="picocluster-claw-leds",
            config=line_config,
        )

    def _init_v1(self, chip_path):
        """Initialize using gpiod v1 API (Ubuntu 22.04, gpiod 1.x)."""
        self._api = "v1"
        # v1 uses chip name not path
        chip_name = chip_path.replace("/dev/", "")
        self._chip = gpiod.Chip(chip_name)
        self._data_line = self._chip.get_line(self._data_line_num)
        self._clock_line = self._chip.get_line(self._clock_line_num)
        self._data_line.request(consumer="picocluster-claw-leds", type=gpiod.LINE_REQ_DIR_OUT, default_val=0)
        self._clock_line.request(consumer="picocluster-claw-leds", type=gpiod.LINE_REQ_DIR_OUT, default_val=0)

    def _set_pin(self, line_num, value):
        """Set a GPIO pin high or low."""
        if self._api == "v2":
            val = gpiod.line.Value.ACTIVE if value else gpiod.line.Value.INACTIVE
            self._request.set_value(line_num, val)
        else:
            line = self._data_line if line_num == self._data_line_num else self._clock_line
            line.set_value(1 if value else 0)

    def set_pixel(self, index, r, g, b, brightness=None):
        """Set a single pixel. Brightness 0.0-1.0 (or None to keep current)."""
        if 0 <= index < NUM_LEDS:
            self._pixels[index][0] = r & 0xFF
            self._pixels[index][1] = g & 0xFF
            self._pixels[index][2] = b & 0xFF
            if brightness is not None:
                self._pixels[index][3] = int(max(0, min(1, brightness)) * 31)

    def set_all(self, r, g, b, brightness=None):
        """Set all pixels to the same color."""
        for i in range(NUM_LEDS):
            self.set_pixel(i, r, g, b, brightness)

    def clear(self):
        """Turn off all pixels (must call show() after)."""
        self._pixels = [[0, 0, 0, 0] for _ in range(NUM_LEDS)]

    def set_brightness(self, brightness):
        """Set global brightness for all pixels (0.0-1.0)."""
        b = int(max(0, min(1, brightness)) * 31)
        for p in self._pixels:
            p[3] = b

    def show(self):
        """Push pixel data to the LEDs."""
        # Start frame: 32 bits of zeros
        self._write_byte(0x00)
        self._write_byte(0x00)
        self._write_byte(0x00)
        self._write_byte(0x00)

        # Pixel data: 3-bit header (111) + 5-bit brightness + BGR
        for pixel in self._pixels:
            r, g, b, br = pixel
            self._write_byte(0xE0 | (br & 0x1F))
            self._write_byte(b)
            self._write_byte(g)
            self._write_byte(r)

        # End frame
        for _ in range((NUM_LEDS + 15) // 16):
            self._write_byte(0xFF)

    def _write_byte(self, byte):
        """Bit-bang one byte MSB-first."""
        for i in range(7, -1, -1):
            bit = (byte >> i) & 1
            self._set_pin(self._data_line_num, bit)
            self._set_pin(self._clock_line_num, 1)
            self._set_pin(self._clock_line_num, 0)

    def cleanup(self):
        """Release GPIO lines."""
        self.clear()
        self.show()
        if self._api == "v2":
            self._request.release()
            self._chip.close()
        else:
            self._data_line.release()
            self._clock_line.release()
            self._chip.close()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.cleanup()


# --- Convenience animation functions ---

def sweep(leds, r, g, b, delay=0.05, brightness=0.3):
    """Sweep a color left to right."""
    for i in range(NUM_LEDS):
        leds.clear()
        leds.set_pixel(i, r, g, b, brightness)
        if i > 0:
            leds.set_pixel(i - 1, r, g, b, brightness * 0.3)
        if i < NUM_LEDS - 1:
            leds.set_pixel(i + 1, r, g, b, brightness * 0.1)
        leds.show()
        time.sleep(delay)


def fill(leds, r, g, b, delay=0.06, brightness=0.3):
    """Fill LEDs left to right."""
    for i in range(NUM_LEDS):
        leds.set_pixel(i, r, g, b, brightness)
        leds.show()
        time.sleep(delay)


def pulse(leds, r, g, b, cycles=3, speed=0.02):
    """Pulse all LEDs."""
    import math
    for cycle in range(cycles):
        for step in range(50):
            br = (math.sin(step / 50 * math.pi) ** 2) * 0.5
            leds.set_all(r, g, b, br)
            leds.show()
            time.sleep(speed)


def flash(leds, r, g, b, times=3, on_time=0.1, off_time=0.1, brightness=0.4):
    """Flash all LEDs."""
    for _ in range(times):
        leds.set_all(r, g, b, brightness)
        leds.show()
        time.sleep(on_time)
        leds.clear()
        leds.show()
        time.sleep(off_time)


def rainbow_cycle(leds, cycles=2, delay=0.02, brightness=0.2):
    """Rainbow cycle across all LEDs."""
    for cycle in range(cycles):
        for offset in range(256):
            for i in range(NUM_LEDS):
                hue = ((i * 256 // NUM_LEDS) + offset) % 256
                r, g, b = _hue_to_rgb(hue)
                leds.set_pixel(i, r, g, b, brightness)
            leds.show()
            time.sleep(delay)


def _hue_to_rgb(hue):
    """Convert 0-255 hue to RGB."""
    if hue < 85:
        return hue * 3, 255 - hue * 3, 0
    elif hue < 170:
        hue -= 85
        return 255 - hue * 3, 0, hue * 3
    else:
        hue -= 170
        return 0, hue * 3, 255 - hue * 3

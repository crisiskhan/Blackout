#!/usr/bin/env python3
"""Generate BLACKOUT BUILD BIBLE v3 tree (content + packages + project)."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from v3.common import ROOT, write_json
from v3.emit_app import emit as emit_app
from v3.emit_swift import emit_all as emit_swift
from v3.field import write_all as write_field
from v3.generate_project import generate as generate_project
from v3.slim_packs import main as slim_packs
from v3.vision import write_all as write_vision


def accent() -> None:
    colorset = ROOT / "Blackout" / "Assets.xcassets" / "AccentColor.colorset"
    colorset.mkdir(parents=True, exist_ok=True)
    write_json(
        colorset / "Contents.json",
        {
            "colors": [
                {
                    "color": {
                        "color-space": "srgb",
                        "components": {"alpha": "1.000", "red": "0.957", "green": "0.969", "blue": "0.980"},
                    },
                    "idiom": "universal",
                }
            ],
            "info": {"author": "xcode", "version": 1},
        },
    )
    write_json(ROOT / "Blackout" / "Assets.xcassets" / "Contents.json", {"info": {"author": "xcode", "version": 1}})


def widget_plists() -> None:
    (ROOT / "BlackoutWidgets" / "Info.plist").write_text(
        """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSExtension</key>
	<dict>
		<key>NSExtensionPointIdentifier</key>
		<string>com.apple.widgetkit-extension</string>
	</dict>
	<key>NSSupportsLiveActivities</key>
	<true/>
</dict>
</plist>
"""
    )
    (ROOT / "BlackoutWatch" / "Info.plist").write_text(
        """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>WKWatchOnly</key>
	<true/>
	<key>WKCompanionAppBundleIdentifier</key>
	<string>com.crisiskhan.blackout</string>
</dict>
</plist>
"""
    )


def main() -> None:
    write_field()
    write_vision()
    slim_packs()
    emit_swift()
    emit_app()
    accent()
    widget_plists()
    generate_project()
    print("v3 generate complete")


if __name__ == "__main__":
    main()

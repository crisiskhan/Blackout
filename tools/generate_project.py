#!/usr/bin/env python3
"""Generate Xcode project. AppIcon comes from brand/emblem.jpeg. Verify DefaultPack USGS tiles. No network."""
from __future__ import annotations

import hashlib
import json
import math
import os
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def oid(name: str) -> str:
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()


def png_chunk(tag: bytes, data: bytes) -> bytes:
    crc = zlib.crc32(tag + data) & 0xFFFFFFFF
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)


def write_png(path: Path, width: int, height: int, pixels: bytes) -> None:
    """pixels: RGBA rows concatenated, length width*height*4."""
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)
        raw.extend(pixels[y * stride : (y + 1) * stride])
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", ihdr)
        + png_chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + png_chunk(b"IEND", b"")
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


def lonlat_to_tile(lon: float, lat: float, z: int) -> tuple[int, int]:
    n = 2**z
    x = int((lon + 180.0) / 360.0 * n)
    lat_rad = math.radians(lat)
    y = int((1.0 - math.log(math.tan(lat_rad) + 1.0 / math.cos(lat_rad)) / math.pi) / 2.0 * n)
    return x, y


def tile_to_lonlat(x: float, y: float, z: int) -> tuple[float, float]:
    n = 2.0**z
    lon = x / n * 360.0 - 180.0
    lat_rad = math.atan(math.sinh(math.pi * (1 - 2 * y / n)))
    return lon, math.degrees(lat_rad)


def sample_elevation(lon: float, lat: float) -> float:
    """Synthetic Front Range: plains east, foothills, high peaks west."""
    plains = 1600.0
    # West is higher. Denver ~ -105, 39.74, ~1600m. Evans ~ -105.64, 39.59, ~4300m.
    west = max(0.0, (-lon - 104.9) / 0.8)
    ridge = math.sin((lat - 39.4) * 8.0) * 0.15 + math.cos((lon + 105.3) * 10.0) * 0.1
    return plains + west * 2800.0 + ridge * 400.0


def make_tile_pixels(z: int, x: int, y: int, size: int = 256) -> bytes:
    west, north = tile_to_lonlat(x, y, z)
    east, south = tile_to_lonlat(x + 1, y + 1, z)
    pix = bytearray(size * size * 4)
    for py in range(size):
        lat = north + (south - north) * (py / (size - 1))
        for px in range(size):
            lon = west + (east - west) * (px / (size - 1))
            elev = sample_elevation(lon, lat)
            t = min(1.0, max(0.0, (elev - 1500.0) / 2800.0))
            # Dark dusk terrain: void-green valleys → steel ridges → silver snow
            r = int(12 + t * 180)
            g = int(16 + t * 160)
            b = int(22 + t * 140)
            # Grid so the sample is obviously tiled, not a real USGS extract
            if px % 64 == 0 or py % 64 == 0:
                r, g, b = min(255, r + 18), min(255, g + 18), min(255, b + 22)
            # Corner SAMPLE marks
            if px < 6 or py < 6 or px > size - 7 or py > size - 7:
                r, g, b = 28, 32, 40
            i = (py * size + px) * 4
            pix[i : i + 4] = bytes((r, g, b, 255))
    # Stamp a small "S" block in the top-left so tiles are labeled as sample
    for py in range(10, 28):
        for px in range(10, 22):
            i = (py * size + px) * 4
            pix[i : i + 4] = bytes((197, 205, 214, 255))
    return bytes(pix)


def generate_default_pack() -> None:
    """Do not rewrite USGS field-pack tiles. generate_project.py is offline."""
    pack = ROOT / "Blackout" / "DefaultPack"
    manifest_path = pack / "manifest.json"
    if not manifest_path.is_file():
        raise SystemExit("DefaultPack/manifest.json missing")
    manifest = json.loads(manifest_path.read_text())
    if manifest.get("kind") != "field-pack":
        raise SystemExit("DefaultPack must stay USGS field-pack tiles; will not generate stubs")
    tiles_root = pack / "tiles"
    need = int(manifest.get("tileCount") or 0)
    pngs = list(tiles_root.rglob("*.png")) if tiles_root.is_dir() else []
    if len(pngs) < need:
        raise SystemExit(f"DefaultPack has {len(pngs)} PNGs, manifest tileCount is {need}")
    for rel in ("tiles/10/211/387.png", "tiles/12/848/1553.png"):
        path = pack / rel
        if not path.is_file() or path.stat().st_size < 8000:
            raise SystemExit(f"DefaultPack probe missing or stub: {rel}")
    print(f"DefaultPack: kept {len(pngs)} USGS field-pack tiles")


def generate_app_icon() -> None:
    """Rasterize the locked emblem. Never synthesize the old red-disc placeholder."""
    import shutil
    import subprocess

    emblem = ROOT / "brand" / "emblem.jpeg"
    icon_dir = ROOT / "Blackout" / "Assets.xcassets" / "AppIcon.appiconset"
    dest = icon_dir / "AppIcon.png"
    if not emblem.is_file():
        raise SystemExit("brand/emblem.jpeg missing; will not synthesize a red-disc AppIcon")
    icon_dir.mkdir(parents=True, exist_ok=True)
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg:
        subprocess.run(
            [
                ffmpeg,
                "-y",
                "-i",
                str(emblem),
                "-vf",
                "scale=1024:1024:flags=lanczos",
                "-pix_fmt",
                "rgb24",
                str(dest),
            ],
            check=True,
            capture_output=True,
        )
    elif dest.is_file() and dest.stat().st_size > 50_000:
        print("AppIcon: kept existing emblem PNG (ffmpeg not available)")
    else:
        raise SystemExit("ffmpeg required to render AppIcon from brand/emblem.jpeg")
    (icon_dir / "Contents.json").write_text(
        json.dumps(
            {
                "images": [
                    {
                        "filename": "AppIcon.png",
                        "idiom": "universal",
                        "platform": "ios",
                        "size": "1024x1024",
                    }
                ],
                "info": {"author": "xcode", "version": 1},
            },
            indent=2,
        )
        + "\n"
    )
    print(f"AppIcon: {dest.stat().st_size} bytes from brand/emblem.jpeg")


def generate_accent() -> None:
    colorset = ROOT / "Blackout" / "Assets.xcassets" / "AccentColor.colorset"
    colorset.mkdir(parents=True, exist_ok=True)
    (colorset / "Contents.json").write_text(
        json.dumps(
            {
                "colors": [
                    {
                        "color": {
                            "color-space": "srgb",
                            "components": {
                                "alpha": "1.000",
                                "red": "0.957",
                                "green": "0.969",
                                "blue": "0.980",
                            },
                        },
                        "idiom": "universal",
                    }
                ],
                "info": {"author": "xcode", "version": 1},
            },
            indent=2,
        )
        + "\n"
    )
    (ROOT / "Blackout" / "Assets.xcassets" / "Contents.json").write_text(
        json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n"
    )


PACKAGES = [
    ("BlackoutCore", "BlackoutCore"),
    ("DesignSystem", "DesignSystem"),
    ("Crypto", "BlackoutCrypto"),
    ("Battery", "BlackoutBattery"),
    ("Persistence", "BlackoutPersistence"),
    ("Location", "BlackoutLocation"),
    ("Mesh", "BlackoutMesh"),
    ("Messaging", "Messaging"),
    ("VoicePTT", "VoicePTT"),
    ("Maps", "Maps"),
    ("Packs", "BlackoutPacks"),
    ("SOS", "SOS"),
    ("Expeditions", "Expeditions"),
    ("Field", "Field"),
    ("Settings", "Settings"),
]


def xc_settings(is_target: bool, debug: bool) -> str:
    common = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ANALYZER_NONNULL": "YES",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "COPY_PHASE_STRIP": "NO",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": "18.0",
        "SDKROOT": "iphoneos",
        "SWIFT_VERSION": "5.0",
    }
    if debug:
        common.update(
            {
                "DEBUG_INFORMATION_FORMAT": "dwarf",
                "ENABLE_TESTABILITY": "YES",
                "GCC_DYNAMIC_NO_PIC": "NO",
                "GCC_OPTIMIZATION_LEVEL": "0",
                "ONLY_ACTIVE_ARCH": "YES",
                "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
                "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
                "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
            }
        )
    else:
        common.update(
            {
                "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
                "ENABLE_NS_ASSERTIONS": "NO",
                "SWIFT_COMPILATION_MODE": "wholemodule",
                "SWIFT_OPTIMIZATION_LEVEL": "-O",
                "VALIDATE_PRODUCT": "YES",
                "MTL_ENABLE_DEBUG_INFO": "NO",
            }
        )
    if is_target:
        common.update(
            {
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
                "ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS": "NO",
                "CODE_SIGN_STYLE": "Automatic",
                "CURRENT_PROJECT_VERSION": "19",
                "DEVELOPMENT_TEAM": "",
                "ENABLE_PREVIEWS": "YES",
                "GENERATE_INFOPLIST_FILE": "YES",
                "INFOPLIST_KEY_CFBundleDisplayName": "Blackout",
                "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.navigation",
                "INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription": "Mesh uses Bluetooth only when you opt in. Zero nearby peers is a valid field state. Deny is supported.",
                "INFOPLIST_KEY_NSBluetoothPeripheralUsageDescription": "Mesh uses Bluetooth only when you opt in. Zero nearby peers is a valid field state. Deny is supported.",
                "INFOPLIST_KEY_NSBonjourServices": "_blckout-mesh._tcp",
                "INFOPLIST_KEY_NSLocalNetworkUsageDescription": "Blackout finds one nearby phone on the same local radio. No internet and no account. Deny keeps Map, Guide, and SOS working. Zero nearby is a valid field state.",
                "INFOPLIST_KEY_NSCameraUsageDescription": "Field Vision classifies a still on this device. Deny is supported — Guide and Skills still work.",
                "INFOPLIST_KEY_NSFaceIDUsageDescription": "Optional on-device lock. Nothing is sent anywhere.",
                "INFOPLIST_KEY_NSLocationWhenInUseUsageDescription": "Blackout uses GPS for last-known fix, breadcrumbs, and elevation. Deny is supported. Map pack, compass, messaging, and SOS still work.",
                "INFOPLIST_KEY_NSMicrophoneUsageDescription": "Voice PTT records locally on this device. Deny is supported.",
                    "INFOPLIST_KEY_NSMotionUsageDescription": "Compass heading and step-length dead reckoning when GPS is denied or cold. Deny is supported.",
                    "INFOPLIST_KEY_NSSpeechRecognitionUsageDescription": "On-device speech for the Field guide ask bar. If denied, type instead.",
                "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
                "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
                "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
                "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
                "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
                "INFOPLIST_KEY_UIUserInterfaceStyle": "Dark",
                "INFOPLIST_KEY_UIStatusBarStyle": "UIStatusBarStyleLightContent",
                "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
                "MARKETING_VERSION": "0.1.0",
                "PRODUCT_BUNDLE_IDENTIFIER": "com.crisiskhan.blackout",
                "PRODUCT_NAME": "$(TARGET_NAME)",
                "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
                "SUPPORTS_MACCATALYST": "NO",
                "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
                "SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD": "NO",
                "SWIFT_EMIT_LOC_STRINGS": "YES",
                "TARGETED_DEVICE_FAMILY": "1,2",
            }
        )
    lines = ["\t\t\t\tisa = XCBuildConfiguration;", "\t\t\t\tbuildSettings = {"]
    for k in sorted(common):
        v = common[k]
        # Commas (TARGETED_DEVICE_FAMILY = 1,2) and leading dashes (-Onone)
        # must be quoted or the OpenStep plist parser dies on xcodebuild.
        if v == "" or any(c in v for c in ' "$,;') or v.startswith("-"):
            lines.append(f'\t\t\t\t\t{k} = "{v}";')
        else:
            lines.append(f"\t\t\t\t\t{k} = {v};")
    config = "Debug" if debug else "Release"
    lines.append("\t\t\t\t};")
    lines.append(f"\t\t\t\tname = {config};")
    return "\n".join(lines)


def generate_xcodeproj() -> None:
    ids = {
        "app_ref": oid("app_ref"),
        "sync": oid("sync_blackout"),
        "fw": oid("fw_phase"),
        "root": oid("root_group"),
        "products": oid("products_group"),
        "target": oid("native_target"),
        "target_conf": oid("target_conf_list"),
        "sources": oid("sources_phase"),
        "resources": oid("resources_phase"),
        "project": oid("project_object"),
        "project_conf": oid("project_conf_list"),
        "proj_debug": oid("proj_debug"),
        "proj_release": oid("proj_release"),
        "tgt_debug": oid("tgt_debug"),
        "tgt_release": oid("tgt_release"),
        "pack_ref": oid("pack_folder_ref"),
        "copy_script": oid("copy_defaultpack_phase"),
        "guide_ref": oid("guide_folder_ref"),
        "copy_guide": oid("copy_guidepack_phase"),
        "sync_ex": oid("sync_exceptions"),
        "sync_res_ex": oid("sync_resources_ex"),
    }
    pkg_ref = {folder: oid(f"pkgref-{folder}") for folder, _ in PACKAGES}
    pkg_dep = {product: oid(f"pkgdep-{product}") for _, product in PACKAGES}
    pkg_link = {product: oid(f"pkglink-{product}") for _, product in PACKAGES}

    dep_lines = ",\n".join(
        f"\t\t\t\t{pkg_dep[product]} /* {product} */" for _, product in PACKAGES
    )
    ref_lines = ",\n".join(
        f"\t\t\t\t{pkg_ref[folder]} /* XCLocalSwiftPackageReference \"Packages/{folder}\" */"
        for folder, _ in PACKAGES
    )
    fw_files = ",\n".join(
        f"\t\t\t\t{pkg_link[product]} /* {product} in Frameworks */" for _, product in PACKAGES
    )

    build_files = []
    for _, product in PACKAGES:
        build_files.append(
            f"\t\t{pkg_link[product]} /* {product} in Frameworks */ = {{isa = PBXBuildFile; productRef = {pkg_dep[product]} /* {product} */; }};"
        )

    copy_script_raw = """set -e
exec "${SRCROOT}/tools/copy_defaultpack.sh"
"""
    copy_script = copy_script_raw.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    copy_guide_raw = """set -e
SRC="${SRCROOT}/Blackout/GuidePack"
DST="${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/GuidePack"
if [ ! -f "${SRC}/manifest.json" ]; then
  echo "error: GuidePack missing at ${SRC}" >&2
  exit 1
fi
mkdir -p "${DST}"
ditto "${SRC}" "${DST}"
echo "Copied GuidePack -> ${DST}"
test -f "${DST}/manifest.json"
"""
    copy_guide = copy_guide_raw.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")

    local_refs = []
    for folder, _ in PACKAGES:
        local_refs.append(
            f"""\t\t{pkg_ref[folder]} /* XCLocalSwiftPackageReference \"Packages/{folder}\" */ = {{
\t\t\tisa = XCLocalSwiftPackageReference;
\t\t\trelativePath = Packages/{folder};
\t\t}};"""
        )
    product_deps = []
    for folder, product in PACKAGES:
        product_deps.append(
            f"""\t\t{pkg_dep[product]} /* {product} */ = {{
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tpackage = {pkg_ref[folder]} /* XCLocalSwiftPackageReference \"Packages/{folder}\" */;
\t\t\tproductName = {product};
\t\t}};"""
        )

    pbx = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 77;
	objects = {{

/* Begin PBXBuildFile section */
{chr(10).join(build_files)}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		{ids['app_ref']} /* Blackout.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Blackout.app; sourceTree = BUILT_PRODUCTS_DIR; }};
		{ids['pack_ref']} /* DefaultPack */ = {{isa = PBXFileReference; explicitFileType = folder; name = DefaultPack; path = Blackout/DefaultPack; sourceTree = "<group>"; }};
		{ids['guide_ref']} /* GuidePack */ = {{isa = PBXFileReference; explicitFileType = folder; name = GuidePack; path = Blackout/GuidePack; sourceTree = "<group>"; }};
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		{ids['sync']} /* Blackout */ = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			exceptions = (
				{ids['sync_ex']} /* Exceptions for "Blackout" folder in "Blackout" target */,
				{ids['sync_res_ex']} /* Exceptions for "Blackout" folder in Resources */,
			);
			explicitFolders = (
				DefaultPack,
				GuidePack,
			);
			path = Blackout;
			sourceTree = "<group>";
		}};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
		{ids['fw']} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
{fw_files},
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{ids['root']} = {{
			isa = PBXGroup;
			children = (
				{ids['sync']} /* Blackout */,
				{ids['pack_ref']} /* DefaultPack */,
				{ids['guide_ref']} /* GuidePack */,
				{ids['products']} /* Products */,
			);
			sourceTree = "<group>";
		}};
		{ids['products']} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{ids['app_ref']} /* Blackout.app */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{ids['target']} /* Blackout */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {ids['target_conf']} /* Build configuration list for PBXNativeTarget "Blackout" */;
			buildPhases = (
				{ids['sources']} /* Sources */,
				{ids['fw']} /* Frameworks */,
				{ids['resources']} /* Resources */,
				{ids['copy_script']} /* Copy DefaultPack into app bundle */,
				{ids['copy_guide']} /* Copy GuidePack into app bundle */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				{ids['sync']} /* Blackout */,
			);
			name = Blackout;
			packageProductDependencies = (
{dep_lines},
			);
			productName = Blackout;
			productReference = {ids['app_ref']} /* Blackout.app */;
			productType = "com.apple.product-type.application";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{ids['project']} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1600;
				LastUpgradeCheck = 1600;
				TargetAttributes = {{
					{ids['target']} = {{
						CreatedOnToolsVersion = 16.0;
					}};
				}};
			}};
			buildConfigurationList = {ids['project_conf']} /* Build configuration list for PBXProject "Blackout" */;
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = {ids['root']};
			minimizedProjectReferenceProxies = 1;
			compatibilityVersion = "Xcode 16.0";
			packageReferences = (
{ref_lines},
			);
			preferredProjectObjectVersion = 77;
			productRefGroup = {ids['products']} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{ids['target']} /* Blackout */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{ids['resources']} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{ids['sources']} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin PBXShellScriptBuildPhase section */
		{ids['copy_script']} /* Copy DefaultPack into app bundle */ = {{
			isa = PBXShellScriptBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			inputFileListPaths = (
			);
			inputPaths = (
				"$(SRCROOT)/Blackout/DefaultPack/manifest.json",
				"$(SRCROOT)/Blackout/DefaultPack/tiles/10/211/387.png",
				"$(SRCROOT)/tools/copy_defaultpack.sh",
			);
			name = "Copy DefaultPack into app bundle";
			outputFileListPaths = (
			);
			outputPaths = (
				"$(BUILT_PRODUCTS_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/DefaultPack/manifest.json",
				"$(BUILT_PRODUCTS_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/DefaultPack/tiles/10/211/387.png",
			);
			runOnlyForDeploymentPostprocessing = 0;
			shellPath = /bin/sh;
			shellScript = "{copy_script}";
		}};
		{ids['copy_guide']} /* Copy GuidePack into app bundle */ = {{
			isa = PBXShellScriptBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			inputFileListPaths = (
			);
			inputPaths = (
				"$(SRCROOT)/Blackout/GuidePack/manifest.json",
			);
			name = "Copy GuidePack into app bundle";
			outputFileListPaths = (
			);
			outputPaths = (
				"$(BUILT_PRODUCTS_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/GuidePack/manifest.json",
			);
			runOnlyForDeploymentPostprocessing = 0;
			shellPath = /bin/sh;
			shellScript = "{copy_guide}";
		}};
/* End PBXShellScriptBuildPhase section */

/* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section */
		{ids['sync_ex']} /* Exceptions for "Blackout" folder in "Blackout" target */ = {{
			isa = PBXFileSystemSynchronizedBuildFileExceptionSet;
			membershipExceptions = (
				DefaultPack,
				GuidePack,
			);
			target = {ids['target']} /* Blackout */;
		}};
/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */

/* Begin PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet section */
		{ids['sync_res_ex']} /* Exceptions for "Blackout" folder in Resources */ = {{
			isa = PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet;
			buildPhase = {ids['resources']} /* Resources */;
			membershipExceptions = (
				DefaultPack,
				GuidePack,
			);
		}};
/* End PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet section */

/* Begin XCBuildConfiguration section */
		{ids['proj_debug']} /* Debug */ = {{
{xc_settings(False, True)}
		}};
		{ids['proj_release']} /* Release */ = {{
{xc_settings(False, False)}
		}};
		{ids['tgt_debug']} /* Debug */ = {{
{xc_settings(True, True)}
		}};
		{ids['tgt_release']} /* Release */ = {{
{xc_settings(True, False)}
		}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{ids['project_conf']} /* Build configuration list for PBXProject "Blackout" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{ids['proj_debug']} /* Debug */,
				{ids['proj_release']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{ids['target_conf']} /* Build configuration list for PBXNativeTarget "Blackout" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{ids['tgt_debug']} /* Debug */,
				{ids['tgt_release']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */

/* Begin XCLocalSwiftPackageReference section */
{chr(10).join(local_refs)}
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
{chr(10).join(product_deps)}
/* End XCSwiftPackageProductDependency section */
	}};
	rootObject = {ids['project']} /* Project object */;
}}
"""
    # Fix accidental " mar" leftovers if any
    pbx = "\n".join(line.replace(" mar", "") if " mar" in line else line for line in pbx.splitlines())
    pbx += "\n"
    proj = ROOT / "Blackout.xcodeproj"
    proj.mkdir(parents=True, exist_ok=True)
    (proj / "project.pbxproj").write_text(pbx)

    scheme_dir = proj / "xcshareddata" / "xcschemes"
    scheme_dir.mkdir(parents=True, exist_ok=True)
    (scheme_dir / "Blackout.xcscheme").write_text(
        f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{ids['target']}"
               BuildableName = "Blackout.app"
               BlueprintName = "Blackout"
               ReferencedContainer = "container:Blackout.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{ids['target']}"
            BuildableName = "Blackout.app"
            BlueprintName = "Blackout"
            ReferencedContainer = "container:Blackout.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{ids['target']}"
            BuildableName = "Blackout.app"
            BlueprintName = "Blackout"
            ReferencedContainer = "container:Blackout.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""
    )
    print("Wrote Blackout.xcodeproj")


def main() -> None:
    generate_default_pack()
    generate_app_icon()
    generate_accent()
    generate_xcodeproj()
    import subprocess
    subprocess.run(["python3", str(ROOT / "tools" / "generate_guide_pack.py")], check=True)


if __name__ == "__main__":
    main()

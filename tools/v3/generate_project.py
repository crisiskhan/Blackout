"""Xcode 16 project: iOS app + Watch + widgets. CURRENT_PROJECT_VERSION stays 1."""
from __future__ import annotations

import re

from .common import ROOT, oid

# OpenStep unquoted token. Comma is a list separator — `1,2` must be quoted.
_UNQUOTED_VALUE = re.compile(r"^[A-Za-z0-9_./+-]+$")

PACKAGES = [
    ("Tokens", "Tokens"),
    ("BlackBox", "BlackBox"),
    ("PackIO", "PackIO"),
    ("Search", "Search"),
    ("Router", "Router"),
    ("DeadReckoning", "DeadReckoning"),
    ("MeshDTN", "MeshDTN"),
    ("CryptoParty", "CryptoParty"),
    ("PTTAudio", "PTTAudio"),
    ("CommsUI", "CommsUI"),
    ("FieldCorpus", "FieldCorpus"),
    ("FieldStepper", "FieldStepper"),
    ("OfflineSpeech", "OfflineSpeech"),
    ("FieldSpeech", "FieldSpeech"),
    ("VisionCoreML", "VisionCoreML"),
    ("VisionCapture", "VisionCapture"),
    ("KitStore", "KitStore"),
    ("Vitals", "Vitals"),
    ("RedAlert", "RedAlert"),
    ("TimerSync", "TimerSync"),
    ("RosterRoles", "RosterRoles"),
    ("TripBrief", "TripBrief"),
    ("PaperGen", "PaperGen"),
    ("Almanac", "Almanac"),
    ("NightRed", "NightRed"),
    ("BatteryAuction", "BatteryAuction"),
    ("Instruments", "Instruments"),
    ("RegionalPacks", "RegionalPacks"),
    ("MapLibreMap", "MapLibreMap"),
]


def xc_common(debug: bool) -> dict:
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
                "GCC_OPTIMIZATION_LEVEL": "0",
                "ONLY_ACTIVE_ARCH": "YES",
                "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
                "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
            }
        )
    else:
        common.update(
            {
                "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
                "SWIFT_COMPILATION_MODE": "wholemodule",
                "SWIFT_OPTIMIZATION_LEVEL": "-O",
                "VALIDATE_PRODUCT": "YES",
            }
        )
    return common


def pbx_assign(value: object) -> str:
    s = str(value)
    if _UNQUOTED_VALUE.fullmatch(s):
        return s
    escaped = s.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def settings_block(d: dict) -> str:
    lines = ["\t\t\t\tisa = XCBuildConfiguration;", "\t\t\t\tbuildSettings = {"]
    for k in sorted(d):
        lines.append(f"\t\t\t\t\t{k} = {pbx_assign(d[k])};")
    lines.append("\t\t\t\t};")
    return "\n".join(lines)


def assert_openstep_plist(text: str) -> None:
    """Raise ValueError if text is not a well-formed OpenStep plist.

    Matches the CFPropertyList old-style rule that failed GHA:
    `TARGETED_DEVICE_FAMILY = 1,2` is two tokens, so the dictionary
    is missing a semicolon.
    """
    parser = _OpenStepParser(text)
    parser.parse()


class _OpenStepParser:
    def __init__(self, text: str) -> None:
        self.s = text
        self.i = 0
        self.n = len(text)

    def parse(self) -> object:
        obj = self._object()
        self._ws()
        if self.i < self.n:
            raise ValueError(f"OpenStep trailing junk at {self._where()}")
        return obj

    def _where(self) -> str:
        line = self.s.count("\n", 0, self.i) + 1
        return f"line {line} col {self.i - self.s.rfind(chr(10), 0, self.i)}"

    def _ws(self) -> None:
        while self.i < self.n:
            c = self.s[self.i]
            if c in " \t\r\n":
                self.i += 1
                continue
            if c == "/" and self.i + 1 < self.n and self.s[self.i + 1] == "/":
                self.i = self.s.find("\n", self.i)
                if self.i < 0:
                    self.i = self.n
                continue
            if c == "/" and self.i + 1 < self.n and self.s[self.i + 1] == "*":
                end = self.s.find("*/", self.i + 2)
                if end < 0:
                    raise ValueError(f"OpenStep unclosed comment at {self._where()}")
                self.i = end + 2
                continue
            return

    def _peek(self) -> str:
        self._ws()
        return self.s[self.i] if self.i < self.n else ""

    def _eat(self, ch: str) -> None:
        self._ws()
        if self.i >= self.n or self.s[self.i] != ch:
            raise ValueError(f"OpenStep expected {ch!r} at {self._where()}")
        self.i += 1

    def _object(self) -> object:
        c = self._peek()
        if c == "{":
            return self._dict()
        if c == "(":
            return self._array()
        if c == '"':
            return self._quoted()
        if c == "":
            raise ValueError(f"OpenStep unexpected EOF at {self._where()}")
        return self._bare()

    def _dict(self) -> dict:
        self._eat("{")
        out: dict = {}
        while True:
            c = self._peek()
            if c == "}":
                self.i += 1
                return out
            if c == "":
                raise ValueError(f"OpenStep unclosed dictionary at {self._where()}")
            key = self._object()
            self._eat("=")
            value = self._object()
            self._ws()
            if self._peek() != ";":
                raise ValueError(
                    f"OpenStep missing semicolon in dictionary at {self._where()} "
                    f"(after {key}={value!r})"
                )
            self._eat(";")
            out[key] = value

    def _array(self) -> list:
        self._eat("(")
        out: list = []
        while True:
            c = self._peek()
            if c == ")":
                self.i += 1
                return out
            if c == "":
                raise ValueError(f"OpenStep unclosed array at {self._where()}")
            out.append(self._object())
            c = self._peek()
            if c == ",":
                self.i += 1
                continue
            if c == ")":
                self.i += 1
                return out
            raise ValueError(f"OpenStep expected comma or ) in array at {self._where()}")

    def _quoted(self) -> str:
        self._eat('"')
        buf: list[str] = []
        while self.i < self.n:
            c = self.s[self.i]
            self.i += 1
            if c == '"':
                return "".join(buf)
            if c == "\\":
                if self.i >= self.n:
                    raise ValueError(f"OpenStep truncated escape at {self._where()}")
                esc = self.s[self.i]
                self.i += 1
                if esc == "n":
                    buf.append("\n")
                elif esc == "t":
                    buf.append("\t")
                elif esc == "r":
                    buf.append("\r")
                else:
                    buf.append(esc)
                continue
            buf.append(c)
        raise ValueError(f"OpenStep unclosed string at {self._where()}")

    def _bare(self) -> str:
        start = self.i
        while self.i < self.n:
            c = self.s[self.i]
            if c in "{ }()=;,\t\r\n" or (c == "/" and self.i + 1 < self.n and self.s[self.i + 1] in "/*"):
                break
            self.i += 1
        if self.i == start:
            raise ValueError(f"OpenStep empty token at {self._where()}")
        return self.s[start : self.i]


def ios_target_settings(debug: bool) -> dict:
    s = xc_common(debug)
    s.update(
        {
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            "CODE_SIGN_STYLE": "Automatic",
            "CURRENT_PROJECT_VERSION": "1",
            "DEVELOPMENT_TEAM": "",
            "ENABLE_PREVIEWS": "YES",
            "GENERATE_INFOPLIST_FILE": "YES",
            "INFOPLIST_KEY_CFBundleDisplayName": "Blackout",
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.navigation",
            "INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription": "Mesh uses Bluetooth only when you opt in. Tens of meters without LoRa. Deny is supported.",
            "INFOPLIST_KEY_NSBluetoothPeripheralUsageDescription": "Mesh uses Bluetooth only when you opt in. Deny is supported.",
            "INFOPLIST_KEY_NSLocalNetworkUsageDescription": "Mesh uses Bluetooth or peer Wi-Fi only when you join a party. Airplane: no sockets. Deny is supported.",
            "INFOPLIST_KEY_NSBonjourServices": "_blackoutmesh._tcp",
            "INFOPLIST_KEY_NSCameraUsageDescription": "Vision classifies a still on this device. It is a guess. Deny is supported.",
            "INFOPLIST_KEY_NSLocationWhenInUseUsageDescription": "GPS for lock-on, dead reckoning start, and last pip. Deny is supported.",
            "INFOPLIST_KEY_NSMicrophoneUsageDescription": "PTT live and 15s clip stay on this device. Deny is supported.",
            "INFOPLIST_KEY_NSMotionUsageDescription": "Heading for dead reckoning when GNSS dies. Deny is supported.",
            "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
            "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
            "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
            "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
            "INFOPLIST_KEY_UIUserInterfaceStyle": "Dark",
            "INFOPLIST_KEY_NSSupportsLiveActivities": "YES",
            "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
            "MARKETING_VERSION": "0.1.0",
            "PRODUCT_BUNDLE_IDENTIFIER": "com.crisiskhan.blackout",
            "PRODUCT_NAME": "$(TARGET_NAME)",
            "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
            "SUPPORTS_MACCATALYST": "NO",
            "TARGETED_DEVICE_FAMILY": "1,2",
            "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
        }
    )
    return s


def watch_settings(debug: bool) -> dict:
    s = xc_common(debug)
    s.update(
        {
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            "CODE_SIGN_STYLE": "Automatic",
            "CURRENT_PROJECT_VERSION": "1",
            "GENERATE_INFOPLIST_FILE": "YES",
            "INFOPLIST_KEY_CFBundleDisplayName": "Blackout",
            "INFOPLIST_KEY_UIUserInterfaceStyle": "Dark",
            "MARKETING_VERSION": "0.1.0",
            "PRODUCT_BUNDLE_IDENTIFIER": "com.crisiskhan.blackout.watchkitapp",
            "PRODUCT_NAME": "$(TARGET_NAME)",
            "SDKROOT": "watchos",
            "SKIP_INSTALL": "YES",
            "TARGETED_DEVICE_FAMILY": "4",
            "WATCHOS_DEPLOYMENT_TARGET": "11.0",
            "SUPPORTED_PLATFORMS": "watchos watchsimulator",
            "INFOPLIST_FILE": "BlackoutWatch/Info.plist",
            "INFOPLIST_KEY_WKWatchOnly": "YES",
            "INFOPLIST_KEY_WKCompanionAppBundleIdentifier": "com.crisiskhan.blackout",
            "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
        }
    )
    return s


def widget_settings(debug: bool) -> dict:
    s = xc_common(debug)
    s.update(
        {
            "CODE_SIGN_STYLE": "Automatic",
            "CURRENT_PROJECT_VERSION": "1",
            "GENERATE_INFOPLIST_FILE": "YES",
            "INFOPLIST_KEY_CFBundleDisplayName": "Blackout Widgets",
            "INFOPLIST_KEY_NSSupportsLiveActivities": "YES",
            "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks",
            "MARKETING_VERSION": "0.1.0",
            "PRODUCT_BUNDLE_IDENTIFIER": "com.crisiskhan.blackout.widgets",
            "PRODUCT_NAME": "$(TARGET_NAME)",
            "SKIP_INSTALL": "YES",
            "TARGETED_DEVICE_FAMILY": "1,2",
            "APPLICATION_EXTENSION_API_ONLY": "YES",
            "INFOPLIST_FILE": "BlackoutWidgets/Info.plist",
            "IPHONEOS_DEPLOYMENT_TARGET": "18.0",
            "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
            "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
        }
    )
    return s


def generate() -> None:
    pkg_paths = [(f"Packages/{folder}", product) for folder, product in PACKAGES]
    pkg_paths.append(("Vendor/MapLibre", "MapLibre"))
    ids = {k: oid(k) for k in [
        "app_ref", "watch_ref", "widget_ref", "sync_app", "sync_watch", "sync_widget",
        "fw_app", "fw_watch", "fw_widget", "root", "products", "tgt_app", "tgt_watch", "tgt_widget",
        "conf_app", "conf_watch", "conf_widget", "src_app", "src_watch", "src_widget",
        "res_app", "res_watch", "res_widget", "project", "proj_conf",
        "proj_debug", "proj_release", "app_debug", "app_release", "watch_debug", "watch_release",
        "widget_debug", "widget_release", "pack_ref", "pack_build", "copy_script",
        "sync_ex", "sync_watch_ex", "sync_widget_ex", "embed_watch", "embed_widget", "dep_watch", "dep_widget",
        "proxy_watch", "proxy_widget",
    ]}
    pkg_ref = {path: oid(f"pkgref-{path}") for path, _ in pkg_paths}
    pkg_dep = {product: oid(f"pkgdep-{product}") for _, product in pkg_paths}
    pkg_link = {product: oid(f"pkglink-{product}") for _, product in pkg_paths}

    dep_lines = ",\n".join(f"\t\t\t\t{pkg_dep[p]} /* {p} */" for _, p in pkg_paths)
    ref_lines = ",\n".join(
        f'\t\t\t\t{pkg_ref[path]} /* XCLocalSwiftPackageReference "{path}" */' for path, _ in pkg_paths
    )
    fw_files = ",\n".join(f"\t\t\t\t{pkg_link[p]} /* {p} in Frameworks */" for _, p in pkg_paths)
    build_files = [
        f"\t\t{pkg_link[p]} /* {p} in Frameworks */ = {{isa = PBXBuildFile; productRef = {pkg_dep[p]} /* {p} */; }};"
        for _, p in pkg_paths
    ]
    build_files.append(
        f"\t\t{ids['pack_build']} /* Resources in Resources */ = {{isa = PBXBuildFile; fileRef = {ids['pack_ref']} /* Resources */; }};"
    )
    build_files.append(
        f"\t\t{ids['embed_watch']} /* BlackoutWatch.app in Embed Watch Content */ = {{isa = PBXBuildFile; fileRef = {ids['watch_ref']} /* BlackoutWatch.app */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};"
    )
    build_files.append(
        f"\t\t{ids['embed_widget']} /* BlackoutWidgets.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {ids['widget_ref']} /* BlackoutWidgets.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};"
    )

    copy_script_raw = """set -e
SRC="${SRCROOT}/Resources"
DST="${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/Resources"
if [ ! -f "${SRC}/Packs/catalog.json" ]; then
  echo "error: Resources/Packs/catalog.json missing" >&2
  exit 1
fi
mkdir -p "${DST}"
ditto "${SRC}" "${DST}"
test -f "${DST}/Packs/catalog.json"
test -f "${DST}/Field/field.core.json"
"""
    copy_script = copy_script_raw.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")

    local_refs = "\n".join(
        f'''\t\t{pkg_ref[path]} /* XCLocalSwiftPackageReference "{path}" */ = {{
\t\t\tisa = XCLocalSwiftPackageReference;
\t\t\trelativePath = {path};
\t\t}};'''
        for path, _ in pkg_paths
    )
    product_deps = "\n".join(
        f'''\t\t{pkg_dep[p]} /* {p} */ = {{
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tpackage = {pkg_ref[path]} /* XCLocalSwiftPackageReference "{path}" */;
\t\t\tproductName = {p};
\t\t}};'''
        for path, p in pkg_paths
    )

    def cfg(name: str, settings: dict, debug: bool) -> str:
        body = settings_block(settings)
        return f"\t\t{ids[name]} /* {'Debug' if debug else 'Release'} */ = {{\n{body}\n\t\t\t\tname = {'Debug' if debug else 'Release'};\n\t\t}};"

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
		{ids['watch_ref']} /* BlackoutWatch.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = BlackoutWatch.app; sourceTree = BUILT_PRODUCTS_DIR; }};
		{ids['widget_ref']} /* BlackoutWidgets.appex */ = {{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = BlackoutWidgets.appex; sourceTree = BUILT_PRODUCTS_DIR; }};
		{ids['pack_ref']} /* Resources */ = {{isa = PBXFileReference; lastKnownFileType = folder; name = Resources; path = Resources; sourceTree = "<group>"; }};
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		{ids['sync_app']} /* Blackout */ = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			path = Blackout;
			sourceTree = "<group>";
		}};
		{ids['sync_watch']} /* BlackoutWatch */ = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			exceptions = (
				{ids['sync_watch_ex']} /* Exceptions for "BlackoutWatch" */,
			);
			path = BlackoutWatch;
			sourceTree = "<group>";
		}};
		{ids['sync_widget']} /* BlackoutWidgets */ = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			exceptions = (
				{ids['sync_widget_ex']} /* Exceptions for "BlackoutWidgets" */,
			);
			path = BlackoutWidgets;
			sourceTree = "<group>";
		}};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
		{ids['fw_app']} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
{fw_files},
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{ids['fw_watch']} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{ids['fw_widget']} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{ids['root']} = {{
			isa = PBXGroup;
			children = (
				{ids['sync_app']} /* Blackout */,
				{ids['sync_watch']} /* BlackoutWatch */,
				{ids['sync_widget']} /* BlackoutWidgets */,
				{ids['pack_ref']} /* Resources */,
				{ids['products']} /* Products */,
			);
			sourceTree = "<group>";
		}};
		{ids['products']} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{ids['app_ref']} /* Blackout.app */,
				{ids['watch_ref']} /* BlackoutWatch.app */,
				{ids['widget_ref']} /* BlackoutWidgets.appex */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXCopyFilesBuildPhase section */
		{ids['proxy_watch']} /* Embed Watch Content */ = {{
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "$(CONTENTS_FOLDER_PATH)/Watch";
			dstSubfolderSpec = 16;
			files = (
				{ids['embed_watch']} /* BlackoutWatch.app in Embed Watch Content */,
			);
			name = "Embed Watch Content";
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{ids['proxy_widget']} /* Embed Foundation Extensions */ = {{
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 13;
			files = (
				{ids['embed_widget']} /* BlackoutWidgets.appex in Embed Foundation Extensions */,
			);
			name = "Embed Foundation Extensions";
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXNativeTarget section */
		{ids['tgt_app']} /* Blackout */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {ids['conf_app']} /* Build configuration list for PBXNativeTarget "Blackout" */;
			buildPhases = (
				{ids['src_app']} /* Sources */,
				{ids['fw_app']} /* Frameworks */,
				{ids['res_app']} /* Resources */,
				{ids['copy_script']} /* Copy Resources into app bundle */,
				{ids['proxy_watch']} /* Embed Watch Content */,
				{ids['proxy_widget']} /* Embed Foundation Extensions */,
			);
			buildRules = (
			);
			dependencies = (
				{ids['dep_watch']} /* PBXTargetDependency */,
				{ids['dep_widget']} /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				{ids['sync_app']} /* Blackout */,
			);
			name = Blackout;
			packageProductDependencies = (
{dep_lines},
			);
			productName = Blackout;
			productReference = {ids['app_ref']} /* Blackout.app */;
			productType = "com.apple.product-type.application";
		}};
		{ids['tgt_watch']} /* BlackoutWatch */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {ids['conf_watch']} /* Build configuration list for PBXNativeTarget "BlackoutWatch" */;
			buildPhases = (
				{ids['src_watch']} /* Sources */,
				{ids['fw_watch']} /* Frameworks */,
				{ids['res_watch']} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				{ids['sync_watch']} /* BlackoutWatch */,
			);
			name = BlackoutWatch;
			productName = BlackoutWatch;
			productReference = {ids['watch_ref']} /* BlackoutWatch.app */;
			productType = "com.apple.product-type.application";
		}};
		{ids['tgt_widget']} /* BlackoutWidgets */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {ids['conf_widget']} /* Build configuration list for PBXNativeTarget "BlackoutWidgets" */;
			buildPhases = (
				{ids['src_widget']} /* Sources */,
				{ids['fw_widget']} /* Frameworks */,
				{ids['res_widget']} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				{ids['sync_widget']} /* BlackoutWidgets */,
			);
			name = BlackoutWidgets;
			productName = BlackoutWidgets;
			productReference = {ids['widget_ref']} /* BlackoutWidgets.appex */;
			productType = "com.apple.product-type.app-extension";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{ids['project']} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1600;
				LastUpgradeCheck = 1600;
			}};
			buildConfigurationList = {ids['proj_conf']} /* Build configuration list for PBXProject "Blackout" */;
			compatibilityVersion = "Xcode 16.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				es,
				Base,
			);
			mainGroup = {ids['root']};
			minimizedProjectReferenceProxies = 1;
			packageReferences = (
{ref_lines},
			);
			preferredProjectObjectVersion = 77;
			productRefGroup = {ids['products']} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{ids['tgt_app']} /* Blackout */,
				{ids['tgt_watch']} /* BlackoutWatch */,
				{ids['tgt_widget']} /* BlackoutWidgets */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{ids['res_app']} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{ids['pack_build']} /* Resources in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{ids['res_watch']} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{ids['res_widget']} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{ids['src_app']} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{ids['src_watch']} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{ids['src_widget']} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin PBXShellScriptBuildPhase section */
		{ids['copy_script']} /* Copy Resources into app bundle */ = {{
			isa = PBXShellScriptBuildPhase;
			alwaysOutOfDate = 1;
			buildActionMask = 2147483647;
			files = (
			);
			inputPaths = (
				"$(SRCROOT)/Resources/Packs/catalog.json",
			);
			name = "Copy Resources into app bundle";
			outputPaths = (
				"$(BUILT_PRODUCTS_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/Resources/Packs/catalog.json",
			);
			runOnlyForDeploymentPostprocessing = 0;
			shellPath = /bin/sh;
			shellScript = "{copy_script}";
		}};
/* End PBXShellScriptBuildPhase section */

/* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section */
		{ids['sync_watch_ex']} /* Exceptions for "BlackoutWatch" */ = {{
			isa = PBXFileSystemSynchronizedBuildFileExceptionSet;
			membershipExceptions = (
				Info.plist,
			);
			target = {ids['tgt_watch']} /* BlackoutWatch */;
		}};
		{ids['sync_widget_ex']} /* Exceptions for "BlackoutWidgets" */ = {{
			isa = PBXFileSystemSynchronizedBuildFileExceptionSet;
			membershipExceptions = (
				Info.plist,
			);
			target = {ids['tgt_widget']} /* BlackoutWidgets */;
		}};
/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */

/* Begin PBXTargetDependency section */
		{ids['dep_watch']} /* PBXTargetDependency */ = {{
			isa = PBXTargetDependency;
			target = {ids['tgt_watch']} /* BlackoutWatch */;
			targetProxy = {oid('proxytwatch')} /* PBXContainerItemProxy */;
		}};
		{ids['dep_widget']} /* PBXTargetDependency */ = {{
			isa = PBXTargetDependency;
			target = {ids['tgt_widget']} /* BlackoutWidgets */;
			targetProxy = {oid('proxytwidget')} /* PBXContainerItemProxy */;
		}};
/* End PBXTargetDependency section */

/* Begin PBXContainerItemProxy section */
		{oid('proxytwatch')} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = {ids['project']} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {ids['tgt_watch']};
			remoteInfo = BlackoutWatch;
		}};
		{oid('proxytwidget')} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = {ids['project']} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {ids['tgt_widget']};
			remoteInfo = BlackoutWidgets;
		}};
/* End PBXContainerItemProxy section */

/* Begin XCBuildConfiguration section */
{cfg('proj_debug', xc_common(True), True)}
{cfg('proj_release', xc_common(False), False)}
{cfg('app_debug', ios_target_settings(True), True)}
{cfg('app_release', ios_target_settings(False), False)}
{cfg('watch_debug', watch_settings(True), True)}
{cfg('watch_release', watch_settings(False), False)}
{cfg('widget_debug', widget_settings(True), True)}
{cfg('widget_release', widget_settings(False), False)}
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{ids['proj_conf']} /* Build configuration list for PBXProject "Blackout" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{ids['proj_debug']} /* Debug */,
				{ids['proj_release']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{ids['conf_app']} /* Build configuration list for PBXNativeTarget "Blackout" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{ids['app_debug']} /* Debug */,
				{ids['app_release']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{ids['conf_watch']} /* Build configuration list for PBXNativeTarget "BlackoutWatch" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{ids['watch_debug']} /* Debug */,
				{ids['watch_release']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{ids['conf_widget']} /* Build configuration list for PBXNativeTarget "BlackoutWidgets" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{ids['widget_debug']} /* Debug */,
				{ids['widget_release']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */

/* Begin XCLocalSwiftPackageReference section */
{local_refs}
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
{product_deps}
/* End XCSwiftPackageProductDependency section */
	}};
	rootObject = {ids['project']} /* Project object */;
}}
"""
    proj = ROOT / "Blackout.xcodeproj"
    proj.mkdir(parents=True, exist_ok=True)
    assert_openstep_plist(pbx)
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
               BlueprintIdentifier = "{ids['tgt_app']}"
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
            BlueprintIdentifier = "{ids['tgt_app']}"
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
            BlueprintIdentifier = "{ids['tgt_app']}"
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

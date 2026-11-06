#!/usr/bin/env python3
"""Generate a small, deterministic Xcode project for GuestBook Helper.

The project intentionally has one app target and no package dependencies.  It is
equivalent to project.yml (kept for XcodeGen users) and opens with Xcode 15+.
"""
from __future__ import annotations

import hashlib
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "GuestBookHelper.xcodeproj"
SOURCE_ROOT = ROOT / "GuestBookHelper"
BUNDLE_ID = "com.n1c0.guestbookhelper.app"
TARGET_NAME = "GuestBookHelper"


def oid(key: str) -> str:
    return hashlib.md5(key.encode("utf-8")).hexdigest().upper()[:24]


def q(value: str) -> str:
    """PBX plist string quoting."""
    if value == "":
        return '""'
    safe = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_$./-")
    if all(ch in safe for ch in value):
        return value
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'


def list_block(values, indent=4):
    pad = "\t" * indent
    if not values:
        return "()"
    inner = "".join(f"{pad}\t{q(v)},\n" for v in values)
    return "(\n" + inner + pad + ")"


# Directory groups.  The key is the group path under GuestBookHelper.
GROUPS = [
    ("App", "App"),
    ("Models", "Models"),
    ("Services", "Services"),
    ("DesignSystem", "DesignSystem"),
    ("Views", "Views"),
    ("Views/Components", "Components"),
    ("Views/Inventory", "Inventory"),
    ("Views/Overview", "Overview"),
    ("Views/Barcode", "Barcode"),
    ("Views/Stores", "Stores"),
    ("Views/Settings", "Settings"),
    ("Resources", "Resources"),
    ("Resources/LaunchImages", "LaunchImages"),
]

swift_files = sorted(SOURCE_ROOT.rglob("*.swift"))
resource_files = [
    SOURCE_ROOT / "Resources/Assets.xcassets",
    SOURCE_ROOT / "Resources/PrivacyInfo.xcprivacy",
]
file_types = {
    ".swift": "sourcecode.swift",
    ".xcassets": "folder.assetcatalog",
    ".xcprivacy": "text.xml",
    ".plist": "text.plist.xml",
}

refs: list[tuple[str, str, str, str]] = []  # id, path, type, group key
build_files: list[tuple[str, str, str]] = []  # id, ref id, name

for path in swift_files:
    rel = path.relative_to(SOURCE_ROOT)
    group = "Resources" if rel.parts[0] == "Resources" else None
    if rel.parts[0] == "Views" and len(rel.parts) >= 3:
        group = "Views/" + rel.parts[1]
    elif rel.parts[0] == "Views":
        group = "Views"
    else:
        group = rel.parts[0]
    ref = oid("ref:" + str(rel))
    build = oid("build:" + str(rel))
    refs.append((ref, path.name, "sourcecode.swift", group))
    build_files.append((build, ref, path.name))

refs.append((oid("ref:Assets.xcassets"), "Assets.xcassets", "folder.assetcatalog", "Resources"))
refs.append((oid("ref:PrivacyInfo.xcprivacy"), "PrivacyInfo.xcprivacy", "text.xml", "Resources"))
refs.append((oid("ref:Info.plist"), "Info.plist", "text.plist.xml", "Resources"))

launch_images = sorted((SOURCE_ROOT / "Resources/LaunchImages").glob("*.png"))
for path in launch_images:
    refs.append((oid("ref:LaunchImages/" + path.name), path.name, "image.png", "Resources/LaunchImages"))

resource_build_files = [
    (oid("build:Assets.xcassets"), oid("ref:Assets.xcassets"), "Assets.xcassets"),
    (oid("build:PrivacyInfo.xcprivacy"), oid("ref:PrivacyInfo.xcprivacy"), "PrivacyInfo.xcprivacy"),
]
for path in launch_images:
    resource_build_files.append((oid("build:LaunchImages/" + path.name), oid("ref:LaunchImages/" + path.name), path.name))

# Group ids and child groups.
group_id = {key: oid("group:" + key) for key, _ in GROUPS}
child_groups: dict[str, list[str]] = {key: [] for key, _ in GROUPS}
group_files: dict[str, list[str]] = {key: [] for key, _ in GROUPS}
for ref, path, ftype, group in refs:
    group_files.setdefault(group, []).append(ref)
for key, _ in GROUPS:
    if "/" in key:
        parent = key.rsplit("/", 1)[0]
        child_groups.setdefault(parent, []).append(key)

main_group = oid("group:main")
source_root_group = oid("group:source")
products_group = oid("group:products")
target_id = oid("target:" + TARGET_NAME)
product_ref = oid("ref:product")
sources_phase = oid("phase:sources")
frameworks_phase = oid("phase:frameworks")
resources_phase = oid("phase:resources")
project_id = oid("project")
project_config_list = oid("configlist:project")
target_config_list = oid("configlist:target")
project_debug = oid("config:project:debug")
project_release = oid("config:project:release")
target_debug = oid("config:target:debug")
target_release = oid("config:target:release")

lines: list[str] = []
lines.append("// !$*UTF8*$!")
lines.append("{")
lines.append("\tarchiveVersion = 1;")
lines.append("\tclasses = {")
lines.append("\t};")
lines.append("\tobjectVersion = 56;")
lines.append("\tobjects = {")

# Build files
lines.append("\n/* Begin PBXBuildFile section */")
for build, ref, name in build_files + resource_build_files:
    lines.append(f"\t\t{build} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {name} */; }};")
lines.append("/* End PBXBuildFile section */")

# File references
lines.append("\n/* Begin PBXFileReference section */")
lines.append(f"\t\t{product_ref} /* {TARGET_NAME}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {TARGET_NAME}.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
for ref, path, ftype, _ in refs:
    lines.append(f"\t\t{ref} /* {path} */ = {{isa = PBXFileReference; lastKnownFileType = {ftype}; path = {q(path)}; sourceTree = \"<group>\"; }};")
lines.append("/* End PBXFileReference section */")

# Frameworks
lines.append("\n/* Begin PBXFrameworksBuildPhase section */")
lines.append(f"\t\t{frameworks_phase} /* Frameworks */ = {{")
lines.append("\t\t\tisa = PBXFrameworksBuildPhase;")
lines.append("\t\t\tbuildActionMask = 2147483647;")
lines.append("\t\t\tfiles = (")
lines.append("\t\t\t);")
lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
lines.append("\t\t};")
lines.append("/* End PBXFrameworksBuildPhase section */")

# Groups
lines.append("\n/* Begin PBXGroup section */")
lines.append(f"\t\t{main_group} = {{")
lines.append("\t\t\tisa = PBXGroup;")
lines.append("\t\t\tchildren = (")
lines.append(f"\t\t\t\t{source_root_group} /* GuestBookHelper */,")
lines.append(f"\t\t\t\t{products_group} /* Products */,")
lines.append("\t\t\t);")
lines.append("\t\t\tsourceTree = \"<group>\";")
lines.append("\t\t};")

lines.append(f"\t\t{source_root_group} /* GuestBookHelper */ = {{")
lines.append("\t\t\tisa = PBXGroup;")
lines.append("\t\t\tchildren = (")
for key in ["App", "Models", "Services", "DesignSystem", "Views", "Resources"]:
    lines.append(f"\t\t\t\t{group_id[key]} /* {dict(GROUPS)[key]} */,")
lines.append("\t\t\t);")
lines.append("\t\t\tpath = GuestBookHelper;")
lines.append("\t\t\tsourceTree = \"<group>\";")
lines.append("\t\t};")

for key, name in GROUPS:
    lines.append(f"\t\t{group_id[key]} /* {name} */ = {{")
    lines.append("\t\t\tisa = PBXGroup;")
    lines.append("\t\t\tchildren = (")
    for child in child_groups.get(key, []):
        child_name = dict(GROUPS)[child]
        lines.append(f"\t\t\t\t{group_id[child]} /* {child_name} */,")
    for ref in group_files.get(key, []):
        path = next(p for r, p, _, g in refs if r == ref)
        lines.append(f"\t\t\t\t{ref} /* {path} */,")
    lines.append("\t\t\t);")
    lines.append(f"\t\t\tpath = {q(name)};")
    lines.append("\t\t\tsourceTree = \"<group>\";")
    lines.append("\t\t};")

lines.append(f"\t\t{products_group} /* Products */ = {{")
lines.append("\t\t\tisa = PBXGroup;")
lines.append("\t\t\tchildren = (")
lines.append(f"\t\t\t\t{product_ref} /* {TARGET_NAME}.app */,")
lines.append("\t\t\t);")
lines.append("\t\t\tname = Products;")
lines.append("\t\t\tsourceTree = \"<group>\";")
lines.append("\t\t};")
lines.append("/* End PBXGroup section */")

# Target
lines.append("\n/* Begin PBXNativeTarget section */")
lines.append(f"\t\t{target_id} /* {TARGET_NAME} */ = {{")
lines.append("\t\t\tisa = PBXNativeTarget;")
lines.append(f"\t\t\tbuildConfigurationList = {target_config_list};")
lines.append("\t\t\tbuildPhases = (")
lines.append(f"\t\t\t\t{sources_phase} /* Sources */,")
lines.append(f"\t\t\t\t{frameworks_phase} /* Frameworks */,")
lines.append(f"\t\t\t\t{resources_phase} /* Resources */,")
lines.append("\t\t\t);")
lines.append("\t\t\tbuildRules = (")
lines.append("\t\t\t);")
lines.append("\t\t\tdependencies = (")
lines.append("\t\t\t);")
lines.append(f"\t\t\tname = {TARGET_NAME};")
lines.append(f"\t\t\tproductName = {TARGET_NAME};")
lines.append(f"\t\t\tproductReference = {product_ref} /* {TARGET_NAME}.app */;")
lines.append("\t\t\tproductType = \"com.apple.product-type.application\";")
lines.append("\t\t};")
lines.append("/* End PBXNativeTarget section */")

# Project
lines.append("\n/* Begin PBXProject section */")
lines.append(f"\t\t{project_id} /* Project object */ = {{")
lines.append("\t\t\tisa = PBXProject;")
lines.append("\t\t\tattributes = {")
lines.append("\t\t\t\tBuildIndependentTargetsInParallel = YES;")
lines.append("\t\t\t\tLastUpgradeCheck = 2620;")
lines.append("\t\t\t\tTargetAttributes = {")
lines.append(f"\t\t\t\t\t{target_id} = {{")
lines.append("\t\t\t\t\t\tCreatedOnToolsVersion = 26.2;")
lines.append("\t\t\t\t\t};")
lines.append("\t\t\t\t};")
lines.append("\t\t\t};")
lines.append(f"\t\t\tbuildConfigurationList = {project_config_list};")
lines.append("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
lines.append("\t\t\tdevelopmentRegion = \"zh-Hans\";")
lines.append("\t\t\thasScannedForEncodings = 0;")
lines.append("\t\t\tknownRegions = (")
lines.append("\t\t\t\ten,")
lines.append("\t\t\t\tBase,")
lines.append("\t\t\t\t\"zh-Hans\",")
lines.append("\t\t\t);")
lines.append(f"\t\t\tmainGroup = {main_group};")
lines.append(f"\t\t\tproductRefGroup = {products_group} /* Products */;")
lines.append("\t\t\tprojectDirPath = \"\";")
lines.append("\t\t\tprojectRoot = \"\";")
lines.append("\t\t\ttargets = (")
lines.append(f"\t\t\t\t{target_id} /* {TARGET_NAME} */,")
lines.append("\t\t\t);")
lines.append("\t\t};")
lines.append("/* End PBXProject section */")

# Resources
lines.append("\n/* Begin PBXResourcesBuildPhase section */")
lines.append(f"\t\t{resources_phase} /* Resources */ = {{")
lines.append("\t\t\tisa = PBXResourcesBuildPhase;")
lines.append("\t\t\tbuildActionMask = 2147483647;")
lines.append("\t\t\tfiles = (")
for build, ref, name in resource_build_files:
    lines.append(f"\t\t\t\t{build} /* {name} in Resources */,")
lines.append("\t\t\t);")
lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
lines.append("\t\t};")
lines.append("/* End PBXResourcesBuildPhase section */")

# Sources
lines.append("\n/* Begin PBXSourcesBuildPhase section */")
lines.append(f"\t\t{sources_phase} /* Sources */ = {{")
lines.append("\t\t\tisa = PBXSourcesBuildPhase;")
lines.append("\t\t\tbuildActionMask = 2147483647;")
lines.append("\t\t\tfiles = (")
for build, ref, name in build_files:
    lines.append(f"\t\t\t\t{build} /* {name} in Sources */,")
lines.append("\t\t\t);")
lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
lines.append("\t\t};")
lines.append("/* End PBXSourcesBuildPhase section */")

# Configurations
project_common = [
    ("ALWAYS_SEARCH_USER_PATHS", "NO"),
    ("CLANG_ANALYZER_NONNULL", "YES"),
    ("CLANG_ENABLE_MODULES", "YES"),
    ("CLANG_ENABLE_OBJC_ARC", "YES"),
    ("COPY_PHASE_STRIP", "NO"),
    ("ENABLE_STRICT_OBJC_MSGSEND", "YES"),
    ("GCC_C_LANGUAGE_STANDARD", "gnu11"),
    ("IPHONEOS_DEPLOYMENT_TARGET", "13.0"),
    ("SDKROOT", "iphoneos"),
    ("SWIFT_VERSION", "5.0"),
]
project_debug_settings = project_common + [
    ("DEBUG_INFORMATION_FORMAT", "dwarf"),
    ("ENABLE_TESTABILITY", "YES"),
    ("GCC_OPTIMIZATION_LEVEL", "0"),
    ("GCC_PREPROCESSOR_DEFINITIONS", '("DEBUG=1", "$(inherited)")'),
    ("ONLY_ACTIVE_ARCH", "YES"),
    ("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "DEBUG"),
    ("SWIFT_OPTIMIZATION_LEVEL", '"-Onone"'),
]
project_release_settings = project_common + [
    ("DEBUG_INFORMATION_FORMAT", '"dwarf-with-dsym"'),
    ("ENABLE_NS_ASSERTIONS", "NO"),
    ("SWIFT_COMPILATION_MODE", "wholemodule"),
    ("SWIFT_OPTIMIZATION_LEVEL", '"-O"'),
    ("VALIDATE_PRODUCT", "YES"),
]
target_common = [
    ("ASSETCATALOG_COMPILER_APPICON_NAME", "AppIcon"),
    ("ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME", "AccentColor"),
    ("CODE_SIGN_STYLE", "Automatic"),
    ("CURRENT_PROJECT_VERSION", "9"),
    ("DEVELOPMENT_TEAM", '""'),
    ("ENABLE_PREVIEWS", "YES"),
    ("GENERATE_INFOPLIST_FILE", "NO"),
    ("INFOPLIST_FILE", "GuestBookHelper/Resources/Info.plist"),
    ("IPHONEOS_DEPLOYMENT_TARGET", "13.0"),
    ("LD_RUNPATH_SEARCH_PATHS", '("$(inherited)", "@executable_path/Frameworks")'),
    ("MARKETING_VERSION", "1.8"),
    ("OTHER_LDFLAGS", '("$(inherited)", "-lcompression", "-lsqlite3", "-framework", "AVFoundation", "-framework", "CoreImage", "-framework", "Vision")'),
    ("PRODUCT_BUNDLE_IDENTIFIER", BUNDLE_ID),
    ("PRODUCT_NAME", TARGET_NAME),
    ("SUPPORTS_MACCATALYST", "NO"),
    ("SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD", "NO"),
    ("SWIFT_STRICT_CONCURRENCY", "minimal"),
    ("SWIFT_VERSION", "5.0"),
    ("TARGETED_DEVICE_FAMILY", '"1,2"'),
]
target_debug_settings = target_common
target_release_settings = target_common

lines.append("\n/* Begin XCBuildConfiguration section */")
for name, settings in [("Debug", project_debug_settings), ("Release", project_release_settings)]:
    lines.append(f"\t\t{project_debug if name == 'Debug' else project_release} /* {name} */ = {{")
    lines.append("\t\t\tisa = XCBuildConfiguration;")
    lines.append("\t\t\tbuildSettings = {")
    for key, value in settings:
        lines.append(f"\t\t\t\t{key} = {value};")
    lines.append("\t\t\t};")
    lines.append(f"\t\t\tname = {name};")
    lines.append("\t\t};")
for name, settings in [("Debug", target_debug_settings), ("Release", target_release_settings)]:
    lines.append(f"\t\t{target_debug if name == 'Debug' else target_release} /* {name} */ = {{")
    lines.append("\t\t\tisa = XCBuildConfiguration;")
    lines.append("\t\t\tbuildSettings = {")
    for key, value in settings:
        lines.append(f"\t\t\t\t{key} = {value};")
    lines.append("\t\t\t};")
    lines.append(f"\t\t\tname = {name};")
    lines.append("\t\t};")
lines.append("/* End XCBuildConfiguration section */")

lines.append("\n/* Begin XCConfigurationList section */")
for config_list, debug, release in [
    (project_config_list, project_debug, project_release),
    (target_config_list, target_debug, target_release),
]:
    lines.append(f"\t\t{config_list} = {{")
    lines.append("\t\t\tisa = XCConfigurationList;")
    lines.append("\t\t\tbuildConfigurations = (")
    lines.append(f"\t\t\t\t{debug} /* Debug */,")
    lines.append(f"\t\t\t\t{release} /* Release */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\tdefaultConfigurationIsVisible = 0;")
    lines.append("\t\t\tdefaultConfigurationName = Release;")
    lines.append("\t\t};")
lines.append("/* End XCConfigurationList section */")

lines.append("\t};")
lines.append(f"\trootObject = {project_id} /* Project object */;")
lines.append("}")

PROJECT.mkdir(parents=True, exist_ok=True)
(PROJECT / "project.pbxproj").write_text("\n".join(lines) + "\n", encoding="utf-8")
(PROJECT / "project.xcworkspace").mkdir(parents=True, exist_ok=True)
(PROJECT / "project.xcworkspace" / "contents.xcworkspacedata").write_text(
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<Workspace version = "1.0">\n'
    '   <FileRef location = "self:">\n'
    '   </FileRef>\n'
    '</Workspace>\n',
    encoding="utf-8",
)

schemes = PROJECT / "xcshareddata" / "xcschemes"
schemes.mkdir(parents=True, exist_ok=True)
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "2620"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES"
      runPostActionsOnFailure = "NO">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{target_id}"
               BuildableName = "{TARGET_NAME}.app"
               BlueprintName = "{TARGET_NAME}"
               ReferencedContainer = "container:{TARGET_NAME}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
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
            BlueprintIdentifier = "{target_id}"
            BuildableName = "{TARGET_NAME}.app"
            BlueprintName = "{TARGET_NAME}"
            ReferencedContainer = "container:{TARGET_NAME}.xcodeproj">
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
            BlueprintIdentifier = "{target_id}"
            BuildableName = "{TARGET_NAME}.app"
            BlueprintName = "{TARGET_NAME}"
            ReferencedContainer = "container:{TARGET_NAME}.xcodeproj">
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
'''
(schemes / f"{TARGET_NAME}.xcscheme").write_text(scheme, encoding="utf-8")

print(f"Generated {PROJECT}")
print(f"  Swift files: {len(swift_files)}")
print(f"  Resources: {len(resource_build_files)}")

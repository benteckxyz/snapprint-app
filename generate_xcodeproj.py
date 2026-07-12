#!/usr/bin/env python3
"""
generate_xcodeproj.py
Creates a correct SnapPrint.xcodeproj with proper nested group hierarchy.

File tree expected:
  SnapPrint/                        ← project root
    SnapPrint/                      ← source root (this is the missing level)
      App/
        SnapPrintApp.swift
        AppConfig.swift
      Models/
        ReceiptModel.swift
      Services/
        SquareAPIService.swift
        ImageProcessor.swift
        PrinterService.swift
      Views/
        ReceiptEntryView.swift
        CameraView.swift
        PhotoPreviewView.swift
        Components/
          CountdownOverlay.swift
      Resources/
        Info.plist

Usage:
    python3 generate_xcodeproj.py
    open SnapPrint.xcodeproj
"""

import os
import uuid

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_NAME = "SnapPrint"
BUNDLE_ID    = "xyz.benteck.snapprint"

def uid():
    return uuid.uuid4().hex[:24].upper()

# ─── IDs ─────────────────────────────────────────────────────────────────────
root_group_id             = uid()
snapprint_src_group_id    = uid()  # the inner "SnapPrint/" folder group
app_group_id              = uid()
models_group_id           = uid()
services_group_id         = uid()
views_group_id            = uid()
components_group_id       = uid()
resources_group_id        = uid()
products_group_id         = uid()

main_target_id            = uid()
project_id                = uid()
config_list_id            = uid()
target_config_list_id     = uid()

debug_config_id           = uid()
release_config_id         = uid()
proj_debug_id             = uid()
proj_release_id           = uid()

sources_phase_id          = uid()
resources_phase_id        = uid()
frameworks_phase_id       = uid()

product_ref_id            = uid()

# ─── Source files: (group_id, relative_path_from_source_root, filename) ──────
# relative_path_from_source_root is relative to SnapPrint/SnapPrint/
SOURCE_FILES = [
    (app_group_id,        "App/SnapPrintApp.swift",                   "SnapPrintApp.swift"),
    (app_group_id,        "App/AppConfig.swift",                      "AppConfig.swift"),
    (models_group_id,     "Models/ReceiptModel.swift",                "ReceiptModel.swift"),
    (services_group_id,   "Services/SquareAPIService.swift",          "SquareAPIService.swift"),
    (services_group_id,   "Services/ImageProcessor.swift",            "ImageProcessor.swift"),
    (services_group_id,   "Services/PrinterService.swift",            "PrinterService.swift"),
    (views_group_id,      "Views/ReceiptEntryView.swift",             "ReceiptEntryView.swift"),
    (views_group_id,      "Views/CameraView.swift",                   "CameraView.swift"),
    (views_group_id,      "Views/PhotoPreviewView.swift",             "PhotoPreviewView.swift"),
    (components_group_id, "Views/Components/CountdownOverlay.swift",  "CountdownOverlay.swift"),
]
PLIST_FILE = (resources_group_id, "Resources/Info.plist", "Info.plist")

# Assign IDs to each file
file_ids   = {}   # relative_path → fileRef ID
build_ids  = {}   # relative_path → buildFile ID  (swift only)

for (_, rel, name) in SOURCE_FILES:
    fid = uid()
    file_ids[rel] = fid
    build_ids[rel] = uid()

plist_rel  = PLIST_FILE[1]
plist_name = PLIST_FILE[2]
file_ids[plist_rel] = uid()

# ─── Helpers ─────────────────────────────────────────────────────────────────
def ind(n): return "\t" * n

def pbx_file_ref(fid, name, file_type, path):
    return (f'{ind(2)}{fid} /* {name} */ = '
            f'{{isa = PBXFileReference; lastKnownFileType = {file_type}; '
            f'path = "{path}"; sourceTree = "<group>"; }};')

def pbx_build_file(bid, fid, name):
    return (f'{ind(2)}{bid} /* {name} in Sources */ = '
            f'{{isa = PBXBuildFile; fileRef = {fid} /* {name} */; }};')

def pbx_group(gid, name, children_ids, path=None):
    children = "\n".join(f"{ind(4)}{c}," for c in children_ids)
    loc = f'path = "{path}";' if path else f'name = "{name}";'
    return f"""{ind(2)}{gid} /* {name} */ = {{
{ind(3)}isa = PBXGroup;
{ind(3)}children = (
{children}
{ind(3)});
{ind(3)}{loc}
{ind(3)}sourceTree = "<group>";
{ind(2)}}};"""

# ─── Build sections ───────────────────────────────────────────────────────────

# PBXFileReference
file_ref_lines = []
for (_, rel, name) in SOURCE_FILES:
    file_ref_lines.append(pbx_file_ref(file_ids[rel], name, "sourcecode.swift", name))
file_ref_lines.append(pbx_file_ref(file_ids[plist_rel], plist_name, "text.plist.xml", plist_name))
file_ref_lines.append(
    f'{ind(2)}{product_ref_id} /* {PROJECT_NAME}.app */ = '
    f'{{isa = PBXFileReference; explicitFileType = wrapper.application; '
    f'includeInIndex = 0; path = "{PROJECT_NAME}.app"; sourceTree = BUILT_PRODUCTS_DIR; }};'
)
file_ref_section = "\n".join(file_ref_lines)

# PBXBuildFile (swift only)
build_file_lines = []
for (_, rel, name) in SOURCE_FILES:
    build_file_lines.append(pbx_build_file(build_ids[rel], file_ids[rel], name))
build_file_section = "\n".join(build_file_lines)

# PBXGroup
# leaf groups → each contains its own files
def group_children(group_id):
    return [file_ids[rel] for (gid, rel, _) in SOURCE_FILES if gid == group_id]

app_group        = pbx_group(app_group_id,        "App",        group_children(app_group_id),        path="App")
models_group     = pbx_group(models_group_id,      "Models",     group_children(models_group_id),      path="Models")
services_group   = pbx_group(services_group_id,    "Services",   group_children(services_group_id),    path="Services")
components_group = pbx_group(components_group_id,  "Components", group_children(components_group_id),  path="Components")
resources_group  = pbx_group(resources_group_id,   "Resources",  [file_ids[plist_rel]],                path="Resources")

views_children   = group_children(views_group_id) + [components_group_id]
views_group      = pbx_group(views_group_id,       "Views",      views_children,                       path="Views")

# inner SnapPrint/ source group
src_children = [app_group_id, models_group_id, services_group_id, views_group_id, resources_group_id]
snapprint_src_group = pbx_group(snapprint_src_group_id, "SnapPrint", src_children, path="SnapPrint")

products_group_blk = pbx_group(products_group_id, "Products", [product_ref_id])

# root group (no path – anchors to project dir)
root_group_blk = pbx_group(root_group_id, PROJECT_NAME,
                            [snapprint_src_group_id, products_group_id])

group_section = "\n\n".join([
    root_group_blk,
    products_group_blk,
    snapprint_src_group,
    app_group, models_group, services_group,
    views_group, components_group, resources_group,
])

# Sources build phase
swift_build_refs = "\n".join(
    f'{ind(4)}{build_ids[rel]} /* {name} in Sources */,'
    for (_, rel, name) in SOURCE_FILES
)
sources_phase = f"""{ind(2)}{sources_phase_id} /* Sources */ = {{
{ind(3)}isa = PBXSourcesBuildPhase;
{ind(3)}buildActionMask = 2147483647;
{ind(3)}files = (
{swift_build_refs}
{ind(3)});
{ind(3)}runOnlyForDeploymentPostprocessing = 0;
{ind(2)}}};"""

resources_phase = f"""{ind(2)}{resources_phase_id} /* Resources */ = {{
{ind(3)}isa = PBXResourcesBuildPhase;
{ind(3)}buildActionMask = 2147483647;
{ind(3)}files = (
{ind(3)});
{ind(3)}runOnlyForDeploymentPostprocessing = 0;
{ind(2)}}};"""

frameworks_phase = f"""{ind(2)}{frameworks_phase_id} /* Frameworks */ = {{
{ind(3)}isa = PBXFrameworksBuildPhase;
{ind(3)}buildActionMask = 2147483647;
{ind(3)}files = (
{ind(3)});
{ind(3)}runOnlyForDeploymentPostprocessing = 0;
{ind(2)}}};"""

native_target = f"""{ind(2)}{main_target_id} /* {PROJECT_NAME} */ = {{
{ind(3)}isa = PBXNativeTarget;
{ind(3)}buildConfigurationList = {target_config_list_id};
{ind(3)}buildPhases = (
{ind(4)}{sources_phase_id} /* Sources */,
{ind(4)}{resources_phase_id} /* Resources */,
{ind(4)}{frameworks_phase_id} /* Frameworks */,
{ind(3)});
{ind(3)}buildRules = (
{ind(3)});
{ind(3)}dependencies = (
{ind(3)});
{ind(3)}name = {PROJECT_NAME};
{ind(3)}productName = {PROJECT_NAME};
{ind(3)}productReference = {product_ref_id};
{ind(3)}productType = "com.apple.product-type.application";
{ind(2)}}};"""

project_obj = f"""{ind(2)}{project_id} /* Project object */ = {{
{ind(3)}isa = PBXProject;
{ind(3)}attributes = {{
{ind(4)}BuildIndependentTargetsInParallel = 1;
{ind(4)}LastSwiftUpdateCheck = 1500;
{ind(4)}LastUpgradeCheck = 1500;
{ind(4)}TargetAttributes = {{
{ind(5)}{main_target_id} = {{
{ind(6)}CreatedOnToolsVersion = 15.0;
{ind(5)}}};
{ind(4)}}};
{ind(3)}}};
{ind(3)}buildConfigurationList = {config_list_id};
{ind(3)}compatibilityVersion = "Xcode 14.0";
{ind(3)}developmentRegion = en;
{ind(3)}hasScannedForEncodings = 0;
{ind(3)}knownRegions = (
{ind(4)}en,
{ind(4)}Base,
{ind(3)});
{ind(3)}mainGroup = {root_group_id};
{ind(3)}projectDirPath = "";
{ind(3)}projectRoot = "";
{ind(3)}targets = (
{ind(4)}{main_target_id} /* {PROJECT_NAME} */,
{ind(3)});
{ind(2)}}};"""

def build_config(cfg_id, name, is_target=True):
    base = f"""
{ind(2)}{cfg_id} /* {name} */ = {{
{ind(3)}isa = XCBuildConfiguration;
{ind(3)}buildSettings = {{
{ind(4)}ALWAYS_SEARCH_USER_PATHS = NO;
{ind(4)}CLANG_ENABLE_MODULES = YES;
{ind(4)}IPHONEOS_DEPLOYMENT_TARGET = 16.0;
{ind(4)}SDKROOT = iphoneos;
{ind(4)}SUPPORTED_PLATFORMS = "iphonesimulator iphoneos";
{ind(4)}SWIFT_VERSION = 5.0;
{ind(4)}TARGETED_DEVICE_FAMILY = "1,2";"""
    if is_target:
        base += f"""
{ind(4)}CODE_SIGN_STYLE = Automatic;
{ind(4)}INFOPLIST_FILE = "SnapPrint/Resources/Info.plist";
{ind(4)}PRODUCT_BUNDLE_IDENTIFIER = "{BUNDLE_ID}";
{ind(4)}PRODUCT_NAME = "$(TARGET_NAME)";"""
        if name == "Debug":
            base += f"""
{ind(4)}DEBUG_INFORMATION_FORMAT = dwarf;
{ind(4)}GCC_OPTIMIZATION_LEVEL = 0;
{ind(4)}ONLY_ACTIVE_ARCH = YES;
{ind(4)}SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
{ind(4)}SWIFT_OPTIMIZATION_LEVEL = "-Onone";"""
        else:
            base += f"""
{ind(4)}DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
{ind(4)}SWIFT_COMPILATION_MODE = wholemodule;
{ind(4)}SWIFT_OPTIMIZATION_LEVEL = "-O";
{ind(4)}VALIDATE_PRODUCT = YES;"""
    base += f"""
{ind(3)}}};
{ind(3)}name = {name};
{ind(2)}}};"""
    return base

target_debug_cfg   = build_config(debug_config_id,   "Debug",   is_target=True)
target_release_cfg = build_config(release_config_id,  "Release", is_target=True)
proj_debug_cfg     = build_config(proj_debug_id,      "Debug",   is_target=False)
proj_release_cfg   = build_config(proj_release_id,    "Release", is_target=False)

target_config_list_blk = f"""{ind(2)}{target_config_list_id} /* Build configuration list for PBXNativeTarget "{PROJECT_NAME}" */ = {{
{ind(3)}isa = XCConfigurationList;
{ind(3)}buildConfigurations = (
{ind(4)}{debug_config_id} /* Debug */,
{ind(4)}{release_config_id} /* Release */,
{ind(3)});
{ind(3)}defaultConfigurationIsVisible = 0;
{ind(3)}defaultConfigurationName = Release;
{ind(2)}}};"""

proj_config_list_blk = f"""{ind(2)}{config_list_id} /* Build configuration list for PBXProject "{PROJECT_NAME}" */ = {{
{ind(3)}isa = XCConfigurationList;
{ind(3)}buildConfigurations = (
{ind(4)}{proj_debug_id} /* Debug */,
{ind(4)}{proj_release_id} /* Release */,
{ind(3)});
{ind(3)}defaultConfigurationIsVisible = 0;
{ind(3)}defaultConfigurationName = Release;
{ind(2)}}};"""

pbxproj = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{

/* Begin PBXBuildFile section */
{build_file_section}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{file_ref_section}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
{frameworks_phase}
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
{group_section}
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
{native_target}
/* End PBXNativeTarget section */

/* Begin PBXProject section */
{project_obj}
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
{resources_phase}
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
{sources_phase}
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
{target_debug_cfg}
{target_release_cfg}
{proj_debug_cfg}
{proj_release_cfg}
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
{target_config_list_blk}
{proj_config_list_blk}
/* End XCConfigurationList section */

\t}};
\trootObject = {project_id} /* Project object */;
}}
"""

proj_dir = os.path.join(BASE_DIR, f"{PROJECT_NAME}.xcodeproj")
os.makedirs(proj_dir, exist_ok=True)
out = os.path.join(proj_dir, "project.pbxproj")
with open(out, "w") as f:
    f.write(pbxproj)

print(f"✅ Generated: {out}")
print(f"\n📱 Open in Xcode:")
print(f"   open \"{BASE_DIR}/{PROJECT_NAME}.xcodeproj\"")

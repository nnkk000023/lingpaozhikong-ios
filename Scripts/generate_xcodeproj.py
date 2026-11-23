#!/usr/bin/env python3
"""
零跑智控 iOS 原生工程（Lingpao.xcodeproj）生成器
仅使用 Python 标准库，确保生成规范的 PBXProject、Local SwiftPM 依赖、Metal Shader 与 Widget Extension 嵌套配置。
"""

import hashlib
import os
from pathlib import Path

IOS_ROOT = Path(__file__).resolve().parent.parent
PROJECT_DIR = IOS_ROOT / "Lingpao.xcodeproj"


def stable_id(seed: str) -> str:
    """生成确定性的 24 位大写十六进制 Xcode Object ID"""
    return hashlib.sha256(seed.encode("utf-8")).hexdigest()[:24].upper()


def collect_files():
    app_dir = IOS_ROOT / "LingpaoApp"
    widget_dir = IOS_ROOT / "LingpaoWidgets"
    uitest_dir = IOS_ROOT / "LingpaoAppUITests"

    app_sources = sorted(
        p.relative_to(IOS_ROOT).as_posix()
        for p in app_dir.rglob("*")
        if p.is_file() and p.suffix in {".swift", ".metal"}
    )
    widget_own_sources = sorted(
        p.relative_to(IOS_ROOT).as_posix()
        for p in widget_dir.rglob("*.swift")
        if p.is_file()
    )
    uitest_sources = sorted(
        p.relative_to(IOS_ROOT).as_posix()
        for p in uitest_dir.rglob("*.swift")
        if p.is_file()
    ) if uitest_dir.exists() else []

    shared_widget_sources = [
        "LingpaoApp/Intents/VehicleAppIntents.swift",
        "LingpaoApp/Storage/KeychainStore.swift",
    ]
    for s in shared_widget_sources:
        assert (IOS_ROOT / s).exists(), f"Missing shared source: {s}"

    return app_sources, widget_own_sources, shared_widget_sources, uitest_sources


def quote_pbx(value: str) -> str:
    if value == "" or any(ch in value for ch in " +-./:@$()"):
        escaped = value.replace("\\", "\\\\").replace('"', '\\"')
        return f'"{escaped}"'
    return value


def main():
    app_sources, widget_own_sources, shared_widget_sources, uitest_sources = collect_files()

    # 固定关键节点 ID
    ids = {
        "project": stable_id("PBXProject:Lingpao"),
        "main_group": stable_id("PBXGroup:Main"),
        "products_group": stable_id("PBXGroup:Products"),
        "app_group": stable_id("PBXGroup:LingpaoApp"),
        "widget_group": stable_id("PBXGroup:LingpaoWidgets"),
        "uitest_group": stable_id("PBXGroup:LingpaoAppUITests"),
        "pkg_ref": stable_id("XCLocalSwiftPackageReference:LingpaoCore"),
        "app_pkg_dep": stable_id("XCSwiftPackageProductDependency:App:LingpaoCore"),
        "widget_pkg_dep": stable_id("XCSwiftPackageProductDependency:Widget:LingpaoCore"),
        "app_pkg_bf": stable_id("PBXBuildFile:App:LingpaoCore"),
        "widget_pkg_bf": stable_id("PBXBuildFile:Widget:LingpaoCore"),
        "app_target": stable_id("PBXNativeTarget:LingpaoApp"),
        "widget_target": stable_id("PBXNativeTarget:LingpaoWidgets"),
        "uitest_target": stable_id("PBXNativeTarget:LingpaoAppUITests"),
        "app_product": stable_id("PBXFileReference:LingpaoApp.app"),
        "widget_product": stable_id("PBXFileReference:LingpaoWidgets.appex"),
        "uitest_product": stable_id("PBXFileReference:LingpaoAppUITests.xctest"),
        "embed_widget_bf": stable_id("PBXBuildFile:Embed:LingpaoWidgets.appex"),
        "car_assets_ref": stable_id("PBXFileReference:Assets/car"),
        "car_assets_bf": stable_id("PBXBuildFile:Resources:Assets/car"),
        "app_info_plist": stable_id("PBXFileReference:LingpaoApp/Resources/Info.plist"),
        "app_entitlements": stable_id("PBXFileReference:LingpaoApp/Resources/Lingpao.entitlements"),
        "widget_info_plist": stable_id("PBXFileReference:LingpaoWidgets/Info.plist"),
        "widget_entitlements": stable_id("PBXFileReference:LingpaoWidgets/LingpaoWidgets.entitlements"),
        "app_sources_phase": stable_id("PBXSourcesBuildPhase:LingpaoApp"),
        "app_fw_phase": stable_id("PBXFrameworksBuildPhase:LingpaoApp"),
        "app_res_phase": stable_id("PBXResourcesBuildPhase:LingpaoApp"),
        "app_embed_phase": stable_id("PBXCopyFilesBuildPhase:EmbedWidgets"),
        "widget_sources_phase": stable_id("PBXSourcesBuildPhase:LingpaoWidgets"),
        "widget_fw_phase": stable_id("PBXFrameworksBuildPhase:LingpaoWidgets"),
        "widget_res_phase": stable_id("PBXResourcesBuildPhase:LingpaoWidgets"),
        "uitest_sources_phase": stable_id("PBXSourcesBuildPhase:LingpaoAppUITests"),
        "uitest_fw_phase": stable_id("PBXFrameworksBuildPhase:LingpaoAppUITests"),
        "uitest_res_phase": stable_id("PBXResourcesBuildPhase:LingpaoAppUITests"),
        "proxy_widget": stable_id("PBXContainerItemProxy:LingpaoWidgets"),
        "dep_widget": stable_id("PBXTargetDependency:LingpaoWidgets"),
        "proxy_app_for_uitest": stable_id("PBXContainerItemProxy:AppForUITest"),
        "dep_app_for_uitest": stable_id("PBXTargetDependency:AppForUITest"),
        "proj_cfg_list": stable_id("XCConfigurationList:Project"),
        "proj_debug": stable_id("XCBuildConfiguration:Project:Debug"),
        "proj_release": stable_id("XCBuildConfiguration:Project:Release"),
        "app_cfg_list": stable_id("XCConfigurationList:App"),
        "app_debug": stable_id("XCBuildConfiguration:App:Debug"),
        "app_release": stable_id("XCBuildConfiguration:App:Release"),
        "widget_cfg_list": stable_id("XCConfigurationList:Widget"),
        "widget_debug": stable_id("XCBuildConfiguration:Widget:Debug"),
        "widget_release": stable_id("XCBuildConfiguration:Widget:Release"),
        "uitest_cfg_list": stable_id("XCConfigurationList:UITest"),
        "uitest_debug": stable_id("XCBuildConfiguration:UITest:Debug"),
        "uitest_release": stable_id("XCBuildConfiguration:UITest:Release"),
    }

    all_paths = sorted(set(app_sources + widget_own_sources + uitest_sources))
    file_ref_ids = {p: stable_id(f"PBXFileReference:{p}") for p in all_paths}
    app_build_file_ids = {p: stable_id(f"PBXBuildFile:App:{p}") for p in app_sources}
    widget_all_sources = widget_own_sources + shared_widget_sources
    widget_build_file_ids = {p: stable_id(f"PBXBuildFile:Widget:{p}") for p in widget_all_sources}
    uitest_build_file_ids = {p: stable_id(f"PBXBuildFile:UITest:{p}") for p in uitest_sources}

    lines = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {", "\t};", "\tobjectVersion = 56;", "\tobjects = {"]

    # 1. PBXBuildFile
    lines.append("\n/* Begin PBXBuildFile section */")
    for p in app_sources:
        ftype = "sourcecode.metal" if p.endswith(".metal") else "sourcecode.swift"
        lines.append(f'\t\t{app_build_file_ids[p]} /* {Path(p).name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref_ids[p]} /* {p} */; }};')
    for p in widget_all_sources:
        lines.append(f'\t\t{widget_build_file_ids[p]} /* {Path(p).name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref_ids[p]} /* {p} */; }};')
    for p in uitest_sources:
        lines.append(f'\t\t{uitest_build_file_ids[p]} /* {Path(p).name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref_ids[p]} /* {p} */; }};')
    lines.append(f'\t\t{ids["app_pkg_bf"]} /* LingpaoCore in Frameworks */ = {{isa = PBXBuildFile; productRef = {ids["app_pkg_dep"]} /* LingpaoCore */; }};')
    lines.append(f'\t\t{ids["widget_pkg_bf"]} /* LingpaoCore in Frameworks */ = {{isa = PBXBuildFile; productRef = {ids["widget_pkg_dep"]} /* LingpaoCore */; }};')
    lines.append(f'\t\t{ids["car_assets_bf"]} /* car in Resources */ = {{isa = PBXBuildFile; fileRef = {ids["car_assets_ref"]} /* car */; }};')
    lines.append(f'\t\t{ids["embed_widget_bf"]} /* LingpaoWidgets.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {ids["widget_product"]} /* LingpaoWidgets.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};')
    lines.append("/* End PBXBuildFile section */")

    # 2. PBXContainerItemProxy
    lines.append("\n/* Begin PBXContainerItemProxy section */")
    lines.append(
        f'\t\t{ids["proxy_widget"]} /* PBXContainerItemProxy */ = {{\n'
        f'\t\t\tisa = PBXContainerItemProxy;\n'
        f'\t\t\tcontainerPortal = {ids["project"]} /* Project object */;\n'
        f'\t\t\tproxyType = 1;\n'
        f'\t\t\tremoteGlobalIDString = {ids["widget_target"]};\n'
        f'\t\t\tremoteInfo = LingpaoWidgets;\n'
        f'\t\t}};'
    )
    lines.append(
        f'\t\t{ids["proxy_app_for_uitest"]} /* PBXContainerItemProxy */ = {{\n'
        f'\t\t\tisa = PBXContainerItemProxy;\n'
        f'\t\t\tcontainerPortal = {ids["project"]} /* Project object */;\n'
        f'\t\t\tproxyType = 1;\n'
        f'\t\t\tremoteGlobalIDString = {ids["app_target"]};\n'
        f'\t\t\tremoteInfo = LingpaoApp;\n'
        f'\t\t}};'
    )
    lines.append("/* End PBXContainerItemProxy section */")

    # 3. PBXCopyFilesBuildPhase
    lines.append("\n/* Begin PBXCopyFilesBuildPhase section */")
    lines.append(
        f'\t\t{ids["app_embed_phase"]} /* Embed Foundation Extensions */ = {{\n'
        f'\t\t\tisa = PBXCopyFilesBuildPhase;\n'
        f'\t\t\tbuildActionMask = 2147483647;\n'
        f'\t\t\tdstPath = "";\n'
        f'\t\t\tdstSubfolderSpec = 13;\n'
        f'\t\t\tfiles = (\n'
        f'\t\t\t\t{ids["embed_widget_bf"]} /* LingpaoWidgets.appex in Embed Foundation Extensions */,\n'
        f'\t\t\t);\n'
        f'\t\t\tname = "Embed Foundation Extensions";\n'
        f'\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
        f'\t\t}};'
    )
    lines.append("/* End PBXCopyFilesBuildPhase section */")

    # 4. PBXFileReference
    lines.append("\n/* Begin PBXFileReference section */")
    for p in all_paths:
        ftype = "sourcecode.metal" if p.endswith(".metal") else "sourcecode.swift"
        lines.append(f'\t\t{file_ref_ids[p]} /* {Path(p).name} */ = {{isa = PBXFileReference; lastKnownFileType = {ftype}; path = {quote_pbx(p)}; sourceTree = "<group>"; }};')
    lines.append(f'\t\t{ids["car_assets_ref"]} /* car */ = {{isa = PBXFileReference; lastKnownFileType = folder; path = "LingpaoApp/Resources/Assets/car"; sourceTree = "<group>"; }};')
    lines.append(f'\t\t{ids["app_info_plist"]} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = "LingpaoApp/Resources/Info.plist"; sourceTree = "<group>"; }};')
    lines.append(f'\t\t{ids["app_entitlements"]} /* Lingpao.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = "LingpaoApp/Resources/Lingpao.entitlements"; sourceTree = "<group>"; }};')
    lines.append(f'\t\t{ids["widget_info_plist"]} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = "LingpaoWidgets/Info.plist"; sourceTree = "<group>"; }};')
    lines.append(f'\t\t{ids["widget_entitlements"]} /* LingpaoWidgets.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = "LingpaoWidgets/LingpaoWidgets.entitlements"; sourceTree = "<group>"; }};')
    lines.append(f'\t\t{ids["app_product"]} /* LingpaoApp.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = LingpaoApp.app; sourceTree = BUILT_PRODUCTS_DIR; }};')
    lines.append(f'\t\t{ids["widget_product"]} /* LingpaoWidgets.appex */ = {{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = LingpaoWidgets.appex; sourceTree = BUILT_PRODUCTS_DIR; }};')
    lines.append(f'\t\t{ids["uitest_product"]} /* LingpaoAppUITests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = LingpaoAppUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};')
    lines.append("/* End PBXFileReference section */")

    # 5. PBXFrameworksBuildPhase
    lines.append("\n/* Begin PBXFrameworksBuildPhase section */")
    lines.append(
        f'\t\t{ids["app_fw_phase"]} /* Frameworks */ = {{\n'
        f'\t\t\tisa = PBXFrameworksBuildPhase;\n'
        f'\t\t\tbuildActionMask = 2147483647;\n'
        f'\t\t\tfiles = (\n'
        f'\t\t\t\t{ids["app_pkg_bf"]} /* LingpaoCore in Frameworks */,\n'
        f'\t\t\t);\n'
        f'\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
        f'\t\t}};'
    )
    lines.append(
        f'\t\t{ids["widget_fw_phase"]} /* Frameworks */ = {{\n'
        f'\t\t\tisa = PBXFrameworksBuildPhase;\n'
        f'\t\t\tbuildActionMask = 2147483647;\n'
        f'\t\t\tfiles = (\n'
        f'\t\t\t\t{ids["widget_pkg_bf"]} /* LingpaoCore in Frameworks */,\n'
        f'\t\t\t);\n'
        f'\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
        f'\t\t}};'
    )
    lines.append(
        f'\t\t{ids["uitest_fw_phase"]} /* Frameworks */ = {{\n'
        f'\t\t\tisa = PBXFrameworksBuildPhase;\n'
        f'\t\t\tbuildActionMask = 2147483647;\n'
        f'\t\t\tfiles = (\n'
        f'\t\t\t);\n'
        f'\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
        f'\t\t}};'
    )
    lines.append("/* End PBXFrameworksBuildPhase section */")

    # 6. PBXGroup
    lines.append("\n/* Begin PBXGroup section */")
    lines.append(
        f'\t\t{ids["main_group"]} = {{\n'
        f'\t\t\tisa = PBXGroup;\n'
        f'\t\t\tchildren = (\n'
        f'\t\t\t\t{ids["app_group"]} /* LingpaoApp */,\n'
        f'\t\t\t\t{ids["widget_group"]} /* LingpaoWidgets */,\n'
        f'\t\t\t\t{ids["uitest_group"]} /* LingpaoAppUITests */,\n'
        f'\t\t\t\t{ids["products_group"]} /* Products */,\n'
        f'\t\t\t);\n'
        f'\t\t\tsourceTree = "<group>";\n'
        f'\t\t}};'
    )
    app_children = [file_ref_ids[p] for p in app_sources] + [
        ids["car_assets_ref"],
        ids["app_info_plist"],
        ids["app_entitlements"],
    ]
    lines.append(
        f'\t\t{ids["app_group"]} /* LingpaoApp */ = {{\n'
        f'\t\t\tisa = PBXGroup;\n'
        f'\t\t\tchildren = (\n'
        + "".join(f"\t\t\t\t{cid},\n" for cid in app_children)
        + '\t\t\t);\n\t\t\tname = LingpaoApp;\n\t\t\tsourceTree = "<group>";\n\t\t};'
    )
    widget_children = [file_ref_ids[p] for p in widget_own_sources] + [
        ids["widget_info_plist"],
        ids["widget_entitlements"],
    ]
    lines.append(
        f'\t\t{ids["widget_group"]} /* LingpaoWidgets */ = {{\n'
        f'\t\t\tisa = PBXGroup;\n'
        f'\t\t\tchildren = (\n'
        + "".join(f"\t\t\t\t{cid},\n" for cid in widget_children)
        + '\t\t\t);\n\t\t\tname = LingpaoWidgets;\n\t\t\tsourceTree = "<group>";\n\t\t};'
    )
    uitest_children = [file_ref_ids[p] for p in uitest_sources]
    lines.append(
        f'\t\t{ids["uitest_group"]} /* LingpaoAppUITests */ = {{\n'
        f'\t\t\tisa = PBXGroup;\n'
        f'\t\t\tchildren = (\n'
        + "".join(f"\t\t\t\t{cid},\n" for cid in uitest_children)
        + '\t\t\t);\n\t\t\tname = LingpaoAppUITests;\n\t\t\tsourceTree = "<group>";\n\t\t};'
    )
    lines.append(
        f'\t\t{ids["products_group"]} /* Products */ = {{\n'
        f'\t\t\tisa = PBXGroup;\n'
        f'\t\t\tchildren = (\n'
        f'\t\t\t\t{ids["app_product"]} /* LingpaoApp.app */,\n'
        f'\t\t\t\t{ids["widget_product"]} /* LingpaoWidgets.appex */,\n'
        f'\t\t\t\t{ids["uitest_product"]} /* LingpaoAppUITests.xctest */,\n'
        f'\t\t\t);\n'
        f'\t\t\tname = Products;\n'
        f'\t\t\tsourceTree = "<group>";\n'
        f'\t\t}};'
    )
    lines.append("/* End PBXGroup section */")

    # 7. PBXNativeTarget
    lines.append("\n/* Begin PBXNativeTarget section */")
    lines.append(
        f'\t\t{ids["app_target"]} /* LingpaoApp */ = {{\n'
        f'\t\t\tisa = PBXNativeTarget;\n'
        f'\t\t\tbuildConfigurationList = {ids["app_cfg_list"]} /* Build configuration list for PBXNativeTarget "LingpaoApp" */;\n'
        f'\t\t\tbuildPhases = (\n'
        f'\t\t\t\t{ids["app_sources_phase"]} /* Sources */,\n'
        f'\t\t\t\t{ids["app_fw_phase"]} /* Frameworks */,\n'
        f'\t\t\t\t{ids["app_res_phase"]} /* Resources */,\n'
        f'\t\t\t\t{ids["app_embed_phase"]} /* Embed Foundation Extensions */,\n'
        f'\t\t\t);\n'
        f'\t\t\tbuildRules = (\n\t\t\t);\n'
        f'\t\t\tdependencies = (\n'
        f'\t\t\t\t{ids["dep_widget"]} /* PBXTargetDependency */,\n'
        f'\t\t\t);\n'
        f'\t\t\tname = LingpaoApp;\n'
        f'\t\t\tpackageProductDependencies = (\n'
        f'\t\t\t\t{ids["app_pkg_dep"]} /* LingpaoCore */,\n'
        f'\t\t\t);\n'
        f'\t\t\tproductName = LingpaoApp;\n'
        f'\t\t\tproductReference = {ids["app_product"]} /* LingpaoApp.app */;\n'
        f'\t\t\tproductType = "com.apple.product-type.application";\n'
        f'\t\t}};'
    )
    lines.append(
        f'\t\t{ids["widget_target"]} /* LingpaoWidgets */ = {{\n'
        f'\t\t\tisa = PBXNativeTarget;\n'
        f'\t\t\tbuildConfigurationList = {ids["widget_cfg_list"]} /* Build configuration list for PBXNativeTarget "LingpaoWidgets" */;\n'
        f'\t\t\tbuildPhases = (\n'
        f'\t\t\t\t{ids["widget_sources_phase"]} /* Sources */,\n'
        f'\t\t\t\t{ids["widget_fw_phase"]} /* Frameworks */,\n'
        f'\t\t\t\t{ids["widget_res_phase"]} /* Resources */,\n'
        f'\t\t\t);\n'
        f'\t\t\tbuildRules = (\n\t\t\t);\n'
        f'\t\t\tdependencies = (\n\t\t\t);\n'
        f'\t\t\tname = LingpaoWidgets;\n'
        f'\t\t\tpackageProductDependencies = (\n'
        f'\t\t\t\t{ids["widget_pkg_dep"]} /* LingpaoCore */,\n'
        f'\t\t\t);\n'
        f'\t\t\tproductName = LingpaoWidgets;\n'
        f'\t\t\tproductReference = {ids["widget_product"]} /* LingpaoWidgets.appex */;\n'
        f'\t\t\tproductType = "com.apple.product-type.app-extension";\n'
        f'\t\t}};'
    )
    lines.append(
        f'\t\t{ids["uitest_target"]} /* LingpaoAppUITests */ = {{\n'
        f'\t\t\tisa = PBXNativeTarget;\n'
        f'\t\t\tbuildConfigurationList = {ids["uitest_cfg_list"]} /* Build configuration list for PBXNativeTarget "LingpaoAppUITests" */;\n'
        f'\t\t\tbuildPhases = (\n'
        f'\t\t\t\t{ids["uitest_sources_phase"]} /* Sources */,\n'
        f'\t\t\t\t{ids["uitest_fw_phase"]} /* Frameworks */,\n'
        f'\t\t\t\t{ids["uitest_res_phase"]} /* Resources */,\n'
        f'\t\t\t);\n'
        f'\t\t\tbuildRules = (\n\t\t\t);\n'
        f'\t\t\tdependencies = (\n'
        f'\t\t\t\t{ids["dep_app_for_uitest"]} /* PBXTargetDependency */,\n'
        f'\t\t\t);\n'
        f'\t\t\tname = LingpaoAppUITests;\n'
        f'\t\t\tproductName = LingpaoAppUITests;\n'
        f'\t\t\tproductReference = {ids["uitest_product"]} /* LingpaoAppUITests.xctest */;\n'
        f'\t\t\tproductType = "com.apple.product-type.bundle.ui-testing";\n'
        f'\t\t}};'
    )
    lines.append("/* End PBXNativeTarget section */")

    # 8. PBXProject
    lines.append("\n/* Begin PBXProject section */")
    lines.append(
        f'\t\t{ids["project"]} /* Project object */ = {{\n'
        f'\t\t\tisa = PBXProject;\n'
        f'\t\t\tattributes = {{\n'
        f'\t\t\t\tBuildIndependentTargetsInParallel = 1;\n'
        f'\t\t\t\tLastSwiftUpdateCheck = 1600;\n'
        f'\t\t\t\tLastUpgradeCheck = 1600;\n'
        f'\t\t\t\tTargetAttributes = {{\n'
        f'\t\t\t\t\t{ids["app_target"]} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;\n\t\t\t\t\t}};\n'
        f'\t\t\t\t\t{ids["widget_target"]} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;\n\t\t\t\t\t}};\n'
        f'\t\t\t\t\t{ids["uitest_target"]} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;\n\t\t\t\t\t\tTestTargetID = {ids["app_target"]};\n\t\t\t\t\t}};\n'
        f'\t\t\t\t}};\n'
        f'\t\t\t}};\n'
        f'\t\t\tbuildConfigurationList = {ids["proj_cfg_list"]} /* Build configuration list for PBXProject "Lingpao" */;\n'
        f'\t\t\tcompatibilityVersion = "Xcode 14.0";\n'
        f'\t\t\tdevelopmentRegion = zh-Hans;\n'
        f'\t\t\thasScannedForEncodings = 0;\n'
        f'\t\t\tknownRegions = (\n\t\t\t\t"zh-Hans",\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);\n'
        f'\t\t\tmainGroup = {ids["main_group"]};\n'
        f'\t\t\tpackageReferences = (\n'
        f'\t\t\t\t{ids["pkg_ref"]} /* XCLocalSwiftPackageReference "LingpaoCore" */,\n'
        f'\t\t\t);\n'
        f'\t\t\tproductRefGroup = {ids["products_group"]} /* Products */;\n'
        f'\t\t\tprojectDirPath = "";\n'
        f'\t\t\tprojectRoot = "";\n'
        f'\t\t\ttargets = (\n'
        f'\t\t\t\t{ids["app_target"]} /* LingpaoApp */,\n'
        f'\t\t\t\t{ids["widget_target"]} /* LingpaoWidgets */,\n'
        f'\t\t\t\t{ids["uitest_target"]} /* LingpaoAppUITests */,\n'
        f'\t\t\t);\n'
        f'\t\t}};'
    )
    lines.append("/* End PBXProject section */")

    # 9. PBXResourcesBuildPhase
    lines.append("\n/* Begin PBXResourcesBuildPhase section */")
    lines.append(
        f'\t\t{ids["app_res_phase"]} /* Resources */ = {{\n'
        f'\t\t\tisa = PBXResourcesBuildPhase;\n'
        f'\t\t\tbuildActionMask = 2147483647;\n'
        f'\t\t\tfiles = (\n'
        f'\t\t\t\t{ids["car_assets_bf"]} /* car in Resources */,\n'
        f'\t\t\t);\n'
        f'\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
        f'\t\t}};'
    )
    lines.append(
        f'\t\t{ids["widget_res_phase"]} /* Resources */ = {{\n'
        f'\t\t\tisa = PBXResourcesBuildPhase;\n'
        f'\t\t\tbuildActionMask = 2147483647;\n'
        f'\t\t\tfiles = (\n\t\t\t);\n'
        f'\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
        f'\t\t}};'
    )
    lines.append(
        f'\t\t{ids["uitest_res_phase"]} /* Resources */ = {{\n'
        f'\t\t\tisa = PBXResourcesBuildPhase;\n'
        f'\t\t\tbuildActionMask = 2147483647;\n'
        f'\t\t\tfiles = (\n\t\t\t);\n'
        f'\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
        f'\t\t}};'
    )
    lines.append("/* End PBXResourcesBuildPhase section */")

    # 10. PBXSourcesBuildPhase
    lines.append("\n/* Begin PBXSourcesBuildPhase section */")
    lines.append(
        f'\t\t{ids["app_sources_phase"]} /* Sources */ = {{\n'
        f'\t\t\tisa = PBXSourcesBuildPhase;\n'
        f'\t\t\tbuildActionMask = 2147483647;\n'
        f'\t\t\tfiles = (\n'
        + "".join(f'\t\t\t\t{app_build_file_ids[p]} /* {Path(p).name} in Sources */,\n' for p in app_sources)
        + '\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};'
    )
    lines.append(
        f'\t\t{ids["widget_sources_phase"]} /* Sources */ = {{\n'
        f'\t\t\tisa = PBXSourcesBuildPhase;\n'
        f'\t\t\tbuildActionMask = 2147483647;\n'
        f'\t\t\tfiles = (\n'
        + "".join(f'\t\t\t\t{widget_build_file_ids[p]} /* {Path(p).name} in Sources */,\n' for p in widget_all_sources)
        + '\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};'
    )
    lines.append(
        f'\t\t{ids["uitest_sources_phase"]} /* Sources */ = {{\n'
        f'\t\t\tisa = PBXSourcesBuildPhase;\n'
        f'\t\t\tbuildActionMask = 2147483647;\n'
        f'\t\t\tfiles = (\n'
        + "".join(f'\t\t\t\t{uitest_build_file_ids[p]} /* {Path(p).name} in Sources */,\n' for p in uitest_sources)
        + '\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};'
    )
    lines.append("/* End PBXSourcesBuildPhase section */")

    # 11. PBXTargetDependency
    lines.append("\n/* Begin PBXTargetDependency section */")
    lines.append(
        f'\t\t{ids["dep_widget"]} /* PBXTargetDependency */ = {{\n'
        f'\t\t\tisa = PBXTargetDependency;\n'
        f'\t\t\ttarget = {ids["widget_target"]} /* LingpaoWidgets */;\n'
        f'\t\t\ttargetProxy = {ids["proxy_widget"]} /* PBXContainerItemProxy */;\n'
        f'\t\t}};'
    )
    lines.append(
        f'\t\t{ids["dep_app_for_uitest"]} /* PBXTargetDependency */ = {{\n'
        f'\t\t\tisa = PBXTargetDependency;\n'
        f'\t\t\ttarget = {ids["app_target"]} /* LingpaoApp */;\n'
        f'\t\t\ttargetProxy = {ids["proxy_app_for_uitest"]} /* PBXContainerItemProxy */;\n'
        f'\t\t}};'
    )
    lines.append("/* End PBXTargetDependency section */")

    # 12. XCBuildConfiguration
    lines.append("\n/* Begin XCBuildConfiguration section */")
    common_project_settings = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
        "MTL_FAST_MATH": "YES",
        "SDKROOT": "iphoneos",
        "SUPPORTED_PLATFORMS": '"iphoneos iphonesimulator"',
        "SWIFT_VERSION": "5.0",
        "TARGETED_DEVICE_FAMILY": '"1"',
    }

    def emit_cfg(cid: str, name: str, settings: dict):
        lines.append(f'\t\t{cid} /* {name} */ = {{')
        lines.append("\t\t\tisa = XCBuildConfiguration;")
        lines.append("\t\t\tbuildSettings = {")
        for k, v in sorted(settings.items()):
            lines.append(f"\t\t\t\t{k} = {v};")
        lines.append("\t\t\t};")
        lines.append(f"\t\t\tname = {name};")
        lines.append("\t\t};")

    proj_debug = dict(common_project_settings, **{
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "ENABLE_TESTABILITY": "YES",
        "GCC_OPTIMIZATION_LEVEL": "0",
        "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
        "ONLY_ACTIVE_ARCH": "YES",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": '"DEBUG $(inherited)"',
        "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
    })
    proj_release = dict(common_project_settings, **{
        "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
        "ENABLE_NS_ASSERTIONS": "NO",
        "SWIFT_COMPILATION_MODE": "wholemodule",
    })
    emit_cfg(ids["proj_debug"], "Debug", proj_debug)
    emit_cfg(ids["proj_release"], "Release", proj_release)

    app_common = {
        "CODE_SIGN_ENTITLEMENTS": "LingpaoApp/Resources/Lingpao.entitlements",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": "LingpaoApp/Resources/Info.plist",
        "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks"',
        "MARKETING_VERSION": "1.0.0",
        "PRODUCT_BUNDLE_IDENTIFIER": "com.lingpao.personal.app",
        "PRODUCT_NAME": '"$(TARGET_NAME)"',
        "SWIFT_EMIT_LOC_STRINGS": "YES",
    }
    emit_cfg(ids["app_debug"], "Debug", app_common)
    emit_cfg(ids["app_release"], "Release", app_common)

    widget_common = {
        "APPLICATION_EXTENSION_API_ONLY": "YES",
        "CODE_SIGN_ENTITLEMENTS": "LingpaoWidgets/LingpaoWidgets.entitlements",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": "LingpaoWidgets/Info.plist",
        "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks"',
        "MARKETING_VERSION": "1.0.0",
        "PRODUCT_BUNDLE_IDENTIFIER": "com.lingpao.personal.app.widgets",
        "PRODUCT_NAME": '"$(TARGET_NAME)"',
        "SKIP_INSTALL": "YES",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
    }
    emit_cfg(ids["widget_debug"], "Debug", widget_common)
    emit_cfg(ids["widget_release"], "Release", widget_common)

    uitest_common = {
        "ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES": "YES",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "GENERATE_INFOPLIST_FILE": "YES",
        "MARKETING_VERSION": "1.0.0",
        "PRODUCT_BUNDLE_IDENTIFIER": "com.lingpao.personal.app.uitests",
        "PRODUCT_NAME": '"$(TARGET_NAME)"',
        "SWIFT_EMIT_LOC_STRINGS": "NO",
        "TEST_TARGET_NAME": "LingpaoApp",
    }
    emit_cfg(ids["uitest_debug"], "Debug", uitest_common)
    emit_cfg(ids["uitest_release"], "Release", uitest_common)
    lines.append("/* End XCBuildConfiguration section */")

    # 13. XCConfigurationList
    lines.append("\n/* Begin XCConfigurationList section */")
    for cfg_key, label, d_key, r_key, def_cfg in [
        ("proj_cfg_list", 'PBXProject "Lingpao"', "proj_debug", "proj_release", "Release"),
        ("app_cfg_list", 'PBXNativeTarget "LingpaoApp"', "app_debug", "app_release", "Release"),
        ("widget_cfg_list", 'PBXNativeTarget "LingpaoWidgets"', "widget_debug", "widget_release", "Release"),
        ("uitest_cfg_list", 'PBXNativeTarget "LingpaoAppUITests"', "uitest_debug", "uitest_release", "Release"),
    ]:
        lines.append(
            f'\t\t{ids[cfg_key]} /* Build configuration list for {label} */ = {{\n'
            f'\t\t\tisa = XCConfigurationList;\n'
            f'\t\t\tbuildConfigurations = (\n'
            f'\t\t\t\t{ids[d_key]} /* Debug */,\n'
            f'\t\t\t\t{ids[r_key]} /* Release */,\n'
            f'\t\t\t);\n'
            f'\t\t\tdefaultConfigurationIsVisible = 0;\n'
            f'\t\t\tdefaultConfigurationName = {def_cfg};\n'
            f'\t\t}};'
        )
    lines.append("/* End XCConfigurationList section */")

    # 14. XCLocalSwiftPackageReference & XCSwiftPackageProductDependency
    lines.append("\n/* Begin XCLocalSwiftPackageReference section */")
    lines.append(
        f'\t\t{ids["pkg_ref"]} /* XCLocalSwiftPackageReference "LingpaoCore" */ = {{\n'
        f'\t\t\tisa = XCLocalSwiftPackageReference;\n'
        f'\t\t\trelativePath = LingpaoCore;\n'
        f'\t\t}};'
    )
    lines.append("/* End XCLocalSwiftPackageReference section */")

    lines.append("\n/* Begin XCSwiftPackageProductDependency section */")
    lines.append(
        f'\t\t{ids["app_pkg_dep"]} /* LingpaoCore */ = {{\n'
        f'\t\t\tisa = XCSwiftPackageProductDependency;\n'
        f'\t\t\tproductName = LingpaoCore;\n'
        f'\t\t}};'
    )
    lines.append(
        f'\t\t{ids["widget_pkg_dep"]} /* LingpaoCore */ = {{\n'
        f'\t\t\tisa = XCSwiftPackageProductDependency;\n'
        f'\t\t\tproductName = LingpaoCore;\n'
        f'\t\t}};'
    )
    lines.append("/* End XCSwiftPackageProductDependency section */")

    lines.append(f"\t}};\n\trootObject = {ids['project']} /* Project object */;\n}}")

    PROJECT_DIR.mkdir(parents=True, exist_ok=True)
    pbx_path = PROJECT_DIR / "project.pbxproj"
    pbx_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    # 生成共享 Scheme
    scheme_dir = PROJECT_DIR / "xcshareddata" / "xcschemes"
    scheme_dir.mkdir(parents=True, exist_ok=True)
    scheme_xml = f"""<?xml version="1.0" encoding="UTF-8"?>
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
               BlueprintIdentifier = "{ids['app_target']}"
               BuildableName = "LingpaoApp.app"
               BlueprintName = "LingpaoApp"
               ReferencedContainer = "container:Lingpao.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "NO">
      <Testables>
         <TestableReference
            skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{ids['uitest_target']}"
               BuildableName = "LingpaoAppUITests.xctest"
               BlueprintName = "LingpaoAppUITests"
               ReferencedContainer = "container:Lingpao.xcodeproj">
            </BuildableReference>
         </TestableReference>
         <TestableReference
            skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "LingpaoCoreTests"
               BuildableName = "LingpaoCoreTests"
               BlueprintName = "LingpaoCoreTests"
               ReferencedContainer = "container:LingpaoCore">
            </BuildableReference>
         </TestableReference>
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
            BlueprintIdentifier = "{ids['app_target']}"
            BuildableName = "LingpaoApp.app"
            BlueprintName = "LingpaoApp"
            ReferencedContainer = "container:Lingpao.xcodeproj">
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
            BlueprintIdentifier = "{ids['app_target']}"
            BuildableName = "LingpaoApp.app"
            BlueprintName = "LingpaoApp"
            ReferencedContainer = "container:Lingpao.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
</Scheme>
"""
    (scheme_dir / "LingpaoApp.xcscheme").write_text(scheme_xml, encoding="utf-8")
    print(f"Generated {pbx_path} with {len(app_sources)} app sources and {len(widget_all_sources)} widget sources.")


if __name__ == "__main__":
    main()

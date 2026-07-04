#!/usr/bin/env python3
"""Generate RouteTrace.xcodeproj/project.pbxproj from source tree."""

from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT_NAME = "RouteTrace"
PBXPROJ = ROOT / f"{PROJECT_NAME}.xcodeproj" / "project.pbxproj"

IOS_SOURCES = ROOT / "RouteTrace" / "iOSApp" / "Sources" / "RouteTrace"
WATCH_SOURCES = ROOT / "RouteTrace" / "WatchApp" / "Sources" / "RouteTraceWatch"
TEST_SOURCES = ROOT / "RouteTrace" / "Tests"

IOS_RESOURCES = [
    ROOT / "RouteTrace" / "iOSApp" / "Assets.xcassets",
    ROOT / "RouteTrace" / "iOSApp" / "LaunchScreen.storyboard",
]
WATCH_RESOURCES = [ROOT / "RouteTrace" / "WatchApp" / "Assets.xcassets"]
TEST_RESOURCES = [ROOT / "RouteTrace" / "Tests" / "Fixtures"]

IOS_SUPPORTING = [
    ROOT / "RouteTrace" / "iOSApp" / "Info.plist",
    ROOT / "RouteTrace" / "iOSApp" / "RouteTrace.entitlements",
]
WATCH_SUPPORTING = [
    ROOT / "RouteTrace" / "WatchApp" / "Info.plist",
    ROOT / "RouteTrace" / "WatchApp" / "RouteTraceWatch.entitlements",
]
WIDGET_SOURCES = ROOT / "RouteTrace" / "WatchWidgets" / "Sources" / "RouteTraceWatchWidgets"
WIDGET_SUPPORTING = [
    ROOT / "RouteTrace" / "WatchWidgets" / "Info.plist",
    ROOT / "RouteTrace" / "WatchWidgets" / "RouteTraceWatchWidgets.entitlements",
]


def uid(key: str) -> str:
    return "3" + hashlib.sha1(key.encode()).hexdigest()[:23]


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def file_type(path: Path) -> str:
    suffix = path.suffix
    if suffix == ".swift":
        return "sourcecode.swift"
    if suffix == ".plist":
        return "text.plist.xml"
    if suffix == ".entitlements":
        return "text.plist.entitlements"
    if suffix == ".xcassets":
        return "folder.assetcatalog"
    if suffix == ".storyboard":
        return "file.storyboard"
    return "folder"


def collect_swift_files(base: Path) -> list[Path]:
    return sorted(base.rglob("*.swift"))


def pbxproj_content() -> str:
    ios_swift = collect_swift_files(IOS_SOURCES)
    watch_swift = collect_swift_files(WATCH_SOURCES)
    widget_swift = collect_swift_files(WIDGET_SOURCES)
    test_swift = collect_swift_files(TEST_SOURCES)

    project_id = uid("project")
    ios_target_id = uid("target-ios")
    watch_target_id = uid("target-watch")
    widget_target_id = uid("target-widget")
    test_target_id = uid("target-test")
    ios_product_id = uid("product-ios")
    watch_product_id = uid("product-watch")
    widget_product_id = uid("product-widget")
    test_product_id = uid("product-test")
    ios_sources_phase = uid("sources-ios")
    watch_sources_phase = uid("sources-watch")
    widget_sources_phase = uid("sources-widget")
    test_sources_phase = uid("sources-test")
    ios_resources_phase = uid("resources-ios")
    watch_resources_phase = uid("resources-watch")
    widget_resources_phase = uid("resources-widget")
    test_resources_phase = uid("resources-test")
    ios_frameworks_phase = uid("frameworks-ios")
    watch_frameworks_phase = uid("frameworks-watch")
    widget_frameworks_phase = uid("frameworks-widget")
    test_frameworks_phase = uid("frameworks-test")
    embed_watch_phase = uid("embed-watch")
    embed_bf = uid("embed-watch-build")
    embed_widget_phase = uid("embed-widget")
    embed_widget_bf = uid("embed-widget-build")
    watch_proxy = uid("watch-proxy")
    widget_proxy = uid("widget-proxy")
    watch_dependency = uid("watch-dependency")
    widget_dependency = uid("widget-dependency")
    main_group = uid("main-group")
    ios_group = uid("group-ios")
    watch_group = uid("group-watch")
    widget_group = uid("group-widget")
    tests_group = uid("group-tests")
    products_group = uid("group-products")
    package_ref_id = uid("package-ref")
    package_product_id = uid("package-product")
    proj_config_list = uid("config-project")
    ios_config_list = uid("config-ios")
    watch_config_list = uid("config-watch")
    widget_config_list = uid("config-widget")
    test_config_list = uid("config-test")
    debug_proj = uid("debug-project")
    release_proj = uid("release-project")
    debug_ios = uid("debug-ios")
    release_ios = uid("release-ios")
    debug_watch = uid("debug-watch")
    release_watch = uid("release-watch")
    debug_widget = uid("debug-widget")
    release_widget = uid("release-widget")
    debug_test = uid("debug-test")
    release_test = uid("release-test")

    file_refs: dict[str, str] = {}
    build_file_decls: list[str] = []

    def file_ref(path: Path) -> str:
        key = rel(path)
        if key not in file_refs:
            file_refs[key] = uid(f"fileref:{key}")
        return file_refs[key]

    def add_source(path: Path, target_key: str) -> tuple[str, str]:
        ref = file_ref(path)
        bf = uid(f"build:{target_key}:{rel(path)}")
        build_file_decls.append(
            f"\t\t{bf} /* {rel(path)} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {rel(path)} */; }};"
        )
        return bf, rel(path)

    def add_resource(path: Path, target_key: str) -> tuple[str, str]:
        ref = file_ref(path)
        bf = uid(f"resbuild:{target_key}:{rel(path)}")
        build_file_decls.append(
            f"\t\t{bf} /* {rel(path)} in Resources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {rel(path)} */; }};"
        )
        return bf, rel(path)

    ios_source_entries = [add_source(p, "ios") for p in ios_swift]
    watch_source_entries = [add_source(p, "watch") for p in watch_swift]
    widget_source_entries = [add_source(p, "widget") for p in widget_swift]
    test_source_entries = [add_source(p, "test") for p in test_swift]
    ios_resource_entries = [add_resource(p, "ios") for p in IOS_RESOURCES]
    watch_resource_entries = [add_resource(p, "watch") for p in WATCH_RESOURCES]
    test_resource_entries = [add_resource(p, "test") for p in TEST_RESOURCES]

    for path in IOS_SUPPORTING + WATCH_SUPPORTING + WIDGET_SUPPORTING:
        file_ref(path)

    build_file_decls.append(
        f"\t\t{embed_bf} /* RouteTraceWatch.app in Embed Watch Content */ = {{isa = PBXBuildFile; fileRef = {watch_product_id} /* RouteTraceWatch.app */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};"
    )
    build_file_decls.append(
        f"\t\t{embed_widget_bf} /* RouteTraceWatchWidgets.appex in Embed App Extensions */ = {{isa = PBXBuildFile; fileRef = {widget_product_id} /* RouteTraceWatchWidgets.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};"
    )

    file_ref_lines = [
        f"\t\t{ref_id} /* {key} */ = {{isa = PBXFileReference; lastKnownFileType = {file_type(ROOT / key)}; path = {key}; sourceTree = \"<group>\"; }};"
        for key, ref_id in sorted(file_refs.items())
    ]

    def phase_lines(entries: list[tuple[str, str]]) -> str:
        return "\n".join(f"\t\t\t\t{bf} /* {name} in Sources */," for bf, name in entries)

    def resource_lines(entries: list[tuple[str, str]]) -> str:
        return "\n".join(f"\t\t\t\t{bf} /* {name} in Resources */," for bf, name in entries)

    ios_children = "\n".join(
        f"\t\t\t\t{file_ref(p)} /* {rel(p)} */," for p in ios_swift + IOS_SUPPORTING + IOS_RESOURCES
    )
    watch_children = "\n".join(
        f"\t\t\t\t{file_ref(p)} /* {rel(p)} */," for p in watch_swift + WATCH_SUPPORTING + WATCH_RESOURCES
    )
    widget_children = "\n".join(
        f"\t\t\t\t{file_ref(p)} /* {rel(p)} */," for p in widget_swift + WIDGET_SUPPORTING
    )
    test_children = "\n".join(
        f"\t\t\t\t{file_ref(p)} /* {rel(p)} */," for p in test_swift + TEST_RESOURCES
    )

    return f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 71;
\tobjects = {{

/* Begin PBXBuildFile section */
{chr(10).join(build_file_decls)}
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
\t\t{watch_proxy} /* PBXContainerItemProxy */ = {{
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = {project_id} /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = {watch_target_id};
\t\t\tremoteInfo = RouteTraceWatch;
\t\t}};
\t\t{widget_proxy} /* PBXContainerItemProxy */ = {{
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = {project_id} /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = {widget_target_id};
\t\t\tremoteInfo = RouteTraceWatchWidgets;
\t\t}};
/* End PBXContainerItemProxy section */

/* Begin PBXCopyFilesBuildPhase section */
\t\t{embed_watch_phase} /* Embed Watch Content */ = {{
\t\t\tisa = PBXCopyFilesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tdstPath = "$(CONTENTS_FOLDER_PATH)/Watch";
\t\t\tdstSubfolderSpec = 16;
\t\t\tfiles = (
\t\t\t\t{embed_bf} /* RouteTraceWatch.app in Embed Watch Content */,
\t\t\t);
\t\t\tname = "Embed Watch Content";
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{embed_widget_phase} /* Embed App Extensions */ = {{
\t\t\tisa = PBXCopyFilesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tdstPath = "";
\t\t\tdstSubfolderSpec = 13;
\t\t\tfiles = (
\t\t\t\t{embed_widget_bf} /* RouteTraceWatchWidgets.appex in Embed App Extensions */,
\t\t\t);
\t\t\tname = "Embed App Extensions";
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFileReference section */
{chr(10).join(file_ref_lines)}
\t\t{ios_product_id} /* RouteTrace.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = RouteTrace.app; sourceTree = BUILT_PRODUCTS_DIR; }};
\t\t{watch_product_id} /* RouteTraceWatch.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = RouteTraceWatch.app; sourceTree = BUILT_PRODUCTS_DIR; }};
\t\t{widget_product_id} /* RouteTraceWatchWidgets.appex */ = {{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = RouteTraceWatchWidgets.appex; sourceTree = BUILT_PRODUCTS_DIR; }};
\t\t{test_product_id} /* RouteTraceTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = RouteTraceTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{ios_frameworks_phase} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{watch_frameworks_phase} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{widget_frameworks_phase} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{test_frameworks_phase} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{main_group} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{ios_group} /* iOS */,
\t\t\t\t{watch_group} /* Watch */,
\t\t\t\t{widget_group} /* WatchWidgets */,
\t\t\t\t{tests_group} /* Tests */,
\t\t\t\t{products_group} /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{ios_group} /* iOS */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{ios_children}
\t\t\t);
\t\t\tname = iOS;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{watch_group} /* Watch */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{watch_children}
\t\t\t);
\t\t\tname = Watch;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{widget_group} /* WatchWidgets */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{widget_children}
\t\t\t);
\t\t\tname = WatchWidgets;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{tests_group} /* Tests */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{test_children}
\t\t\t);
\t\t\tname = Tests;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{products_group} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{ios_product_id} /* RouteTrace.app */,
\t\t\t\t{watch_product_id} /* RouteTraceWatch.app */,
\t\t\t\t{widget_product_id} /* RouteTraceWatchWidgets.appex */,
\t\t\t\t{test_product_id} /* RouteTraceTests.xctest */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{ios_target_id} /* RouteTrace */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {ios_config_list} /* Build configuration list for PBXNativeTarget "RouteTrace" */;
\t\t\tbuildPhases = (
\t\t\t\t{ios_sources_phase} /* Sources */,
\t\t\t\t{ios_frameworks_phase} /* Frameworks */,
\t\t\t\t{ios_resources_phase} /* Resources */,
\t\t\t\t{embed_watch_phase} /* Embed Watch Content */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t\t{watch_dependency} /* PBXTargetDependency */,
\t\t\t);
\t\t\tname = RouteTrace;
\t\t\tpackageProductDependencies = (
\t\t\t\t{package_product_id} /* RouteTraceShared */,
\t\t\t);
\t\t\tproductName = RouteTrace;
\t\t\tproductReference = {ios_product_id} /* RouteTrace.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
\t\t{watch_target_id} /* RouteTraceWatch */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {watch_config_list} /* Build configuration list for PBXNativeTarget "RouteTraceWatch" */;
\t\t\tbuildPhases = (
\t\t\t\t{watch_sources_phase} /* Sources */,
\t\t\t\t{watch_frameworks_phase} /* Frameworks */,
\t\t\t\t{watch_resources_phase} /* Resources */,
\t\t\t\t{embed_widget_phase} /* Embed App Extensions */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t\t{widget_dependency} /* PBXTargetDependency */,
\t\t\t);
\t\t\tname = RouteTraceWatch;
\t\t\tpackageProductDependencies = (
\t\t\t\t{package_product_id} /* RouteTraceShared */,
\t\t\t);
\t\t\tproductName = RouteTraceWatch;
\t\t\tproductReference = {watch_product_id} /* RouteTraceWatch.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
\t\t{widget_target_id} /* RouteTraceWatchWidgets */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {widget_config_list} /* Build configuration list for PBXNativeTarget "RouteTraceWatchWidgets" */;
\t\t\tbuildPhases = (
\t\t\t\t{widget_sources_phase} /* Sources */,
\t\t\t\t{widget_frameworks_phase} /* Frameworks */,
\t\t\t\t{widget_resources_phase} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = RouteTraceWatchWidgets;
\t\t\tpackageProductDependencies = (
\t\t\t\t{package_product_id} /* RouteTraceShared */,
\t\t\t);
\t\t\tproductName = RouteTraceWatchWidgets;
\t\t\tproductReference = {widget_product_id} /* RouteTraceWatchWidgets.appex */;
\t\t\tproductType = "com.apple.product-type.app-extension";
\t\t}};
\t\t{test_target_id} /* RouteTraceTests */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {test_config_list} /* Build configuration list for PBXNativeTarget "RouteTraceTests" */;
\t\t\tbuildPhases = (
\t\t\t\t{test_sources_phase} /* Sources */,
\t\t\t\t{test_frameworks_phase} /* Frameworks */,
\t\t\t\t{test_resources_phase} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = RouteTraceTests;
\t\t\tpackageProductDependencies = (
\t\t\t\t{package_product_id} /* RouteTraceShared */,
\t\t\t);
\t\t\tproductName = RouteTraceTests;
\t\t\tproductReference = {test_product_id} /* RouteTraceTests.xctest */;
\t\t\tproductType = "com.apple.product-type.bundle.unit-test";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{project_id} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 2650;
\t\t\t\tLastUpgradeCheck = 2650;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{ios_target_id} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;
\t\t\t\t\t\tProvisioningStyle = Automatic;
\t\t\t\t\t}};
\t\t\t\t\t{watch_target_id} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;
\t\t\t\t\t\tProvisioningStyle = Automatic;
\t\t\t\t\t}};
\t\t\t\t\t{widget_target_id} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;
\t\t\t\t\t\tProvisioningStyle = Automatic;
\t\t\t\t\t}};
\t\t\t\t\t{test_target_id} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;
\t\t\t\t\t\tProvisioningStyle = Automatic;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {proj_config_list} /* Build configuration list for PBXProject "RouteTrace" */;
\t\t\tcompatibilityVersion = "Xcode 16.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {main_group};
\t\t\tminimizedProjectReferenceProxies = 1;
\t\t\tpackageReferences = (
\t\t\t\t{package_ref_id} /* XCLocalSwiftPackageReference "RouteTraceApple" */,
\t\t\t);
\t\t\tproductRefGroup = {products_group} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{ios_target_id} /* RouteTrace */,
\t\t\t\t{watch_target_id} /* RouteTraceWatch */,
\t\t\t\t{widget_target_id} /* RouteTraceWatchWidgets */,
\t\t\t\t{test_target_id} /* RouteTraceTests */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{ios_resources_phase} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{resource_lines(ios_resource_entries)}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{watch_resources_phase} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{resource_lines(watch_resource_entries)}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{widget_resources_phase} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{test_resources_phase} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{resource_lines(test_resource_entries)}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{ios_sources_phase} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{phase_lines(ios_source_entries)}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{watch_sources_phase} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{phase_lines(watch_source_entries)}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{widget_sources_phase} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{phase_lines(widget_source_entries)}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{test_sources_phase} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{phase_lines(test_source_entries)}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
\t\t{watch_dependency} /* PBXTargetDependency */ = {{
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = {watch_target_id} /* RouteTraceWatch */;
\t\t\ttargetProxy = {watch_proxy} /* PBXContainerItemProxy */;
\t\t}};
\t\t{widget_dependency} /* PBXTargetDependency */ = {{
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = {widget_target_id} /* RouteTraceWatchWidgets */;
\t\t\ttargetProxy = {widget_proxy} /* PBXContainerItemProxy */;
\t\t}};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
\t\t{debug_proj} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (
\t\t\t\t\t"DEBUG=1",
\t\t\t\t\t"$(inherited)",
\t\t\t\t);
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSDKROOT = auto;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{release_proj} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tSDKROOT = auto;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{debug_ios} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = RouteTrace/iOSApp/RouteTrace.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_FILE = RouteTrace/iOSApp/Info.plist;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = RouteTrace;
\t\t\t\tINFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.sports";
\t\t\t\tINFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
\t\t\t\tINFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
\t\t\t\tINFOPLIST_KEY_UILaunchStoryboardName = LaunchScreen;
\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = UIInterfaceOrientationPortrait;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 26.0;
\t\t\t\tMARKETING_VERSION = 0.1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.uwe.RouteTrace;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
\t\t\t\tSWIFT_STRICT_CONCURRENCY = complete;
\t\t\t\tSWIFT_VERSION = 6.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = 1;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{release_ios} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = RouteTrace/iOSApp/RouteTrace.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_FILE = RouteTrace/iOSApp/Info.plist;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = RouteTrace;
\t\t\t\tINFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.sports";
\t\t\t\tINFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
\t\t\t\tINFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
\t\t\t\tINFOPLIST_KEY_UILaunchStoryboardName = LaunchScreen;
\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = UIInterfaceOrientationPortrait;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 26.0;
\t\t\t\tMARKETING_VERSION = 0.1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.uwe.RouteTrace;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
\t\t\t\tSWIFT_STRICT_CONCURRENCY = complete;
\t\t\t\tSWIFT_VERSION = 6.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = 1;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{debug_watch} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = RouteTrace/WatchApp/RouteTraceWatch.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_FILE = RouteTrace/WatchApp/Info.plist;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = RouteTrace;
\t\t\t\tINFOPLIST_KEY_WKApplication = YES;
\t\t\t\tINFOPLIST_KEY_WKCompanionAppBundleIdentifier = com.uwe.RouteTrace;
\t\t\t\tMARKETING_VERSION = 0.1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.uwe.RouteTrace.watchkitapp;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSDKROOT = watchos;
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSUPPORTED_PLATFORMS = "watchos watchsimulator";
\t\t\t\tSWIFT_STRICT_CONCURRENCY = complete;
\t\t\t\tSWIFT_VERSION = 6.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = 4;
\t\t\t\tWATCHOS_DEPLOYMENT_TARGET = 26.0;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{release_watch} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = RouteTrace/WatchApp/RouteTraceWatch.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_FILE = RouteTrace/WatchApp/Info.plist;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = RouteTrace;
\t\t\t\tINFOPLIST_KEY_WKApplication = YES;
\t\t\t\tINFOPLIST_KEY_WKCompanionAppBundleIdentifier = com.uwe.RouteTrace;
\t\t\t\tMARKETING_VERSION = 0.1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.uwe.RouteTrace.watchkitapp;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSDKROOT = watchos;
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSUPPORTED_PLATFORMS = "watchos watchsimulator";
\t\t\t\tSWIFT_STRICT_CONCURRENCY = complete;
\t\t\t\tSWIFT_VERSION = 6.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = 4;
\t\t\t\tWATCHOS_DEPLOYMENT_TARGET = 26.0;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{debug_widget} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tCODE_SIGN_ENTITLEMENTS = RouteTrace/WatchWidgets/RouteTraceWatchWidgets.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_FILE = RouteTrace/WatchWidgets/Info.plist;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = RouteTrace;
\t\t\t\tMARKETING_VERSION = 0.1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.uwe.RouteTrace.watchkitapp.widgets;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSDKROOT = watchos;
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSUPPORTED_PLATFORMS = "watchos watchsimulator";
\t\t\t\tSWIFT_STRICT_CONCURRENCY = complete;
\t\t\t\tSWIFT_VERSION = 6.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = 4;
\t\t\t\tWATCHOS_DEPLOYMENT_TARGET = 26.0;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{release_widget} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tCODE_SIGN_ENTITLEMENTS = RouteTrace/WatchWidgets/RouteTraceWatchWidgets.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_FILE = RouteTrace/WatchWidgets/Info.plist;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = RouteTrace;
\t\t\t\tMARKETING_VERSION = 0.1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.uwe.RouteTrace.watchkitapp.widgets;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSDKROOT = watchos;
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSUPPORTED_PLATFORMS = "watchos watchsimulator";
\t\t\t\tSWIFT_STRICT_CONCURRENCY = complete;
\t\t\t\tSWIFT_VERSION = 6.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = 4;
\t\t\t\tWATCHOS_DEPLOYMENT_TARGET = 26.0;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{debug_test} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tBUNDLE_LOADER = "$(TEST_HOST)";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 26.0;
\t\t\t\tMARKETING_VERSION = 0.1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.uwe.RouteTraceTests;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
\t\t\t\tSWIFT_STRICT_CONCURRENCY = complete;
\t\t\t\tSWIFT_VERSION = 6.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = 1;
\t\t\t\tTEST_HOST = "$(BUILT_PRODUCTS_DIR)/RouteTrace.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/RouteTrace";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{release_test} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tBUNDLE_LOADER = "$(TEST_HOST)";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 26.0;
\t\t\t\tMARKETING_VERSION = 0.1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.uwe.RouteTraceTests;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
\t\t\t\tSWIFT_STRICT_CONCURRENCY = complete;
\t\t\t\tSWIFT_VERSION = 6.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = 1;
\t\t\t\tTEST_HOST = "$(BUILT_PRODUCTS_DIR)/RouteTrace.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/RouteTrace";
\t\t\t}};
\t\t\tname = Release;
\t\t}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{ios_config_list} /* Build configuration list for PBXNativeTarget "RouteTrace" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{debug_ios} /* Debug */,
\t\t\t\t{release_ios} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{watch_config_list} /* Build configuration list for PBXNativeTarget "RouteTraceWatch" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{debug_watch} /* Debug */,
\t\t\t\t{release_watch} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{widget_config_list} /* Build configuration list for PBXNativeTarget "RouteTraceWatchWidgets" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{debug_widget} /* Debug */,
\t\t\t\t{release_widget} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{test_config_list} /* Build configuration list for PBXNativeTarget "RouteTraceTests" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{debug_test} /* Debug */,
\t\t\t\t{release_test} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{proj_config_list} /* Build configuration list for PBXProject "RouteTrace" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{debug_proj} /* Debug */,
\t\t\t\t{release_proj} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */

/* Begin XCLocalSwiftPackageReference section */
\t\t{package_ref_id} /* XCLocalSwiftPackageReference "RouteTraceApple" */ = {{
\t\t\tisa = XCLocalSwiftPackageReference;
\t\t\trelativePath = .;
\t\t}};
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
\t\t{package_product_id} /* RouteTraceShared */ = {{
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tproductName = RouteTraceShared;
\t\t\tpackage = {package_ref_id} /* XCLocalSwiftPackageReference "RouteTraceApple" */;
\t\t}};
/* End XCSwiftPackageProductDependency section */
\t}};
\trootObject = {project_id} /* Project object */;
}}
"""


def main() -> None:
    PBXPROJ.parent.mkdir(parents=True, exist_ok=True)
    PBXPROJ.write_text(pbxproj_content())
    print(f"Wrote {PBXPROJ}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Generate a complete Xcode project without XcodeGen or a third-party Python module."""
from pathlib import Path
import hashlib
import json
import plistlib
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'MetaRayRecorder.xcodeproj'
objects = {}
def oid(name): return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
def add(identity, isa, **fields):
    key = oid(identity)
    objects[key] = dict(isa=isa, **fields)
    return key

def config(name, values): return add(name, 'XCBuildConfiguration', buildSettings=values, name=name.split(':')[-1])
def configs(name, debug, release):
    return add(name, 'XCConfigurationList', buildConfigurations=[debug, release],
               defaultConfigurationIsVisible='0', defaultConfigurationName='Release')
def file(path, typ): return add('file:' + path, 'PBXFileReference', lastKnownFileType=typ, path=path, sourceTree='<group>')
def build_file(name, ref): return add('build:' + name, 'PBXBuildFile', fileRef=ref)

app_sources = sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / 'MetaRayRecorder').rglob('*.swift'))
app_refs = [file(path, 'sourcecode.swift') for path in app_sources]
source_builds = [build_file(path, ref) for path, ref in zip(app_sources, app_refs)]
assets_ref = file('MetaRayRecorder/Resources/Assets.xcassets', 'folder.assetcatalog')
info_ref = file('MetaRayRecorder/Resources/Info.plist', 'text.plist.xml')
app_product = add('product:app', 'PBXFileReference', explicitFileType='wrapper.application',
                  includeInIndex='0', path='MetaRayRecorder.app', sourceTree='BUILT_PRODUCTS_DIR')
test_product = add('product:tests', 'PBXFileReference', explicitFileType='wrapper.cfbundle',
                   includeInIndex='0', path='MetaRayRecorderTests.xctest', sourceTree='BUILT_PRODUCTS_DIR')
test_ref = file('Tests/RecorderTests.swift', 'sourcecode.swift')
package_ref = add('package:meta', 'XCRemoteSwiftPackageReference',
    repositoryURL='https://github.com/facebook/meta-wearables-dat-ios',
    requirement=dict(kind='exactVersion', version='1.0.0'))
products, framework_builds = [], []
for name in ('MWDATCore', 'MWDATCamera'):
    prod = add('package-product:' + name, 'XCSwiftPackageProductDependency', package=package_ref, productName=name)
    products.append(prod)
    framework_builds.append(add('framework-build:' + name, 'PBXBuildFile', productRef=prod))
app_sources_phase = add('phase:app-source', 'PBXSourcesBuildPhase', buildActionMask='2147483647', files=source_builds, runOnlyForDeploymentPostprocessing='0')
frameworks_phase = add('phase:app-frameworks', 'PBXFrameworksBuildPhase', buildActionMask='2147483647', files=framework_builds, runOnlyForDeploymentPostprocessing='0')
resources_phase = add('phase:app-resources', 'PBXResourcesBuildPhase', buildActionMask='2147483647', files=[build_file('assets', assets_ref)], runOnlyForDeploymentPostprocessing='0')
embed_phase = add('phase:app-embed', 'PBXCopyFilesBuildPhase', buildActionMask='2147483647', dstPath='', dstSubfolderSpec='10', files=[], name='Embed Frameworks', runOnlyForDeploymentPostprocessing='0')
test_sources_phase = add('phase:tests-source', 'PBXSourcesBuildPhase', buildActionMask='2147483647', files=[build_file('test', test_ref)], runOnlyForDeploymentPostprocessing='0')
test_frameworks_phase = add('phase:tests-frameworks', 'PBXFrameworksBuildPhase', buildActionMask='2147483647',
    files=[add('test-framework-build:' + str(i), 'PBXBuildFile', productRef=prod) for i, prod in enumerate(products)],
    runOnlyForDeploymentPostprocessing='0')

common = dict(SDKROOT='iphoneos', IPHONEOS_DEPLOYMENT_TARGET='17.2', SWIFT_VERSION='5.0',
              SWIFT_STRICT_CONCURRENCY='minimal', CLANG_ENABLE_MODULES='YES', CLANG_ENABLE_OBJC_ARC='YES',
              ENABLE_USER_SCRIPT_SANDBOXING='YES', GCC_C_LANGUAGE_STANDARD='gnu17',
              CLANG_CXX_LANGUAGE_STANDARD='gnu++20', CODE_SIGN_STYLE='Automatic', TARGETED_DEVICE_FAMILY='1',
              SUPPORTED_PLATFORMS='iphoneos iphonesimulator', SUPPORTS_MACCATALYST='NO')
project_debug = config('project:Debug', dict(common, SWIFT_OPTIMIZATION_LEVEL='-Onone', ENABLE_TESTABILITY='YES',
                                            ONLY_ACTIVE_ARCH='YES', DEBUG_INFORMATION_FORMAT='dwarf', SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG'))
project_release = config('project:Release', dict(common, SWIFT_OPTIMIZATION_LEVEL='-O', SWIFT_COMPILATION_MODE='wholemodule',
                                                ONLY_ACTIVE_ARCH='NO', DEBUG_INFORMATION_FORMAT='dwarf-with-dsym'))
app_base = dict(PRODUCT_BUNDLE_IDENTIFIER='fr.personal.metarayrecorder', PRODUCT_NAME='$(TARGET_NAME)',
                INFOPLIST_FILE='MetaRayRecorder/Resources/Info.plist', GENERATE_INFOPLIST_FILE='NO',
                MARKETING_VERSION='1.1.0', CURRENT_PROJECT_VERSION='2',
                ASSETCATALOG_COMPILER_APPICON_NAME='AppIcon', ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES='YES',
                LD_RUNPATH_SEARCH_PATHS=['$(inherited)', '@executable_path/Frameworks'],
                DEVELOPMENT_TEAM='', META_APP_ID='', CLIENT_TOKEN='', ENABLE_PREVIEWS='YES')
app_debug = config('app:Debug', app_base.copy()); app_release = config('app:Release', app_base.copy())
test_base = dict(PRODUCT_BUNDLE_IDENTIFIER='fr.personal.metarayrecorder.tests', PRODUCT_NAME='$(TARGET_NAME)',
                 GENERATE_INFOPLIST_FILE='YES', BUNDLE_LOADER='$(TEST_HOST)',
                 TEST_HOST='$(BUILT_PRODUCTS_DIR)/MetaRayRecorder.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/MetaRayRecorder',
                 LD_RUNPATH_SEARCH_PATHS=['$(inherited)', '@executable_path/Frameworks', '@loader_path/Frameworks'])
test_debug = config('tests:Debug', test_base.copy()); test_release = config('tests:Release', test_base.copy())
proxy = add('proxy:tests', 'PBXContainerItemProxy', containerPortal=oid('project'), proxyType='1',
            remoteGlobalIDString=oid('target:app'), remoteInfo='MetaRayRecorder')
dependency = add('dependency:tests', 'PBXTargetDependency', target=oid('target:app'), targetProxy=proxy)
app_target = add('target:app', 'PBXNativeTarget', name='MetaRayRecorder', productName='MetaRayRecorder',
    productType='com.apple.product-type.application', productReference=app_product,
    buildConfigurationList=configs('configs:app', app_debug, app_release),
    buildPhases=[app_sources_phase, frameworks_phase, resources_phase, embed_phase], buildRules=[],
    dependencies=[], packageProductDependencies=products)
tests_target = add('target:tests', 'PBXNativeTarget', name='MetaRayRecorderTests', productName='MetaRayRecorderTests',
    productType='com.apple.product-type.bundle.unit-test', productReference=test_product,
    buildConfigurationList=configs('configs:tests', test_debug, test_release),
    buildPhases=[test_sources_phase, test_frameworks_phase], buildRules=[], dependencies=[dependency], packageProductDependencies=products)
app_group = add('group:app', 'PBXGroup', name='MetaRayRecorder', children=app_refs + [assets_ref, info_ref], sourceTree='<group>')
tests_group = add('group:tests', 'PBXGroup', name='Tests', children=[test_ref], sourceTree='<group>')
products_group = add('group:products', 'PBXGroup', name='Products', children=[app_product, test_product], sourceTree='<group>')
main_group = add('group:root', 'PBXGroup', children=[app_group, tests_group, products_group], sourceTree='<group>')
project_id = add('project', 'PBXProject', attributes=dict(LastUpgradeCheck='2640', BuildIndependentTargetsInParallel='YES',
    TargetAttributes={app_target: dict(CreatedOnToolsVersion='26.4'), tests_target: dict(CreatedOnToolsVersion='26.4', TestTargetID=app_target)}),
    buildConfigurationList=configs('configs:project', project_debug, project_release), compatibilityVersion='Xcode 14.0',
    developmentRegion='fr', knownRegions=['fr', 'Base'], hasScannedForEncodings='0', mainGroup=main_group,
    productRefGroup=products_group, projectDirPath='', projectRoot='', targets=[app_target, tests_target], packageReferences=[package_ref])

def dump(value, indent=0):
    pad = '\t' * indent
    if isinstance(value, dict):
        return '{\n' + ''.join(pad + '\t' + json.dumps(str(k)) + ' = ' + dump(v, indent + 1) + ';\n' for k, v in value.items()) + pad + '}'
    if isinstance(value, list):
        return '(\n' + ''.join(pad + '\t' + dump(v, indent + 1) + ',\n' for v in value) + pad + ')'
    return json.dumps(str(value), ensure_ascii=True)

PROJECT.mkdir(exist_ok=True)
(PROJECT / 'project.pbxproj').write_text('// !$*UTF8*$!\n' + dump(dict(archiveVersion='1', classes={}, objectVersion='56', objects=objects, rootObject=project_id)) + '\n')
workspace = PROJECT / 'project.xcworkspace'; workspace.mkdir(exist_ok=True)
(workspace / 'contents.xcworkspacedata').write_text('<?xml version="1.0" encoding="UTF-8"?>\n<Workspace version="1.0"><FileRef location="self:"/></Workspace>\n')
schemes = PROJECT / 'xcshareddata' / 'xcschemes'; schemes.mkdir(parents=True, exist_ok=True)
scheme = ET.Element('Scheme', {'LastUpgradeVersion':'2640', 'version':'1.3'})
ba = ET.SubElement(scheme, 'BuildAction', {'parallelizeBuildables':'YES','buildImplicitDependencies':'YES'})
entries = ET.SubElement(ba, 'BuildActionEntries')
def ref(parent, target, name):
    return ET.SubElement(parent, 'BuildableReference', {'BuildableIdentifier':'primary','BlueprintIdentifier':target,
        'BuildableName':name + ('.app' if name == 'MetaRayRecorder' else '.xctest'), 'BlueprintName':name,
        'ReferencedContainer':'container:MetaRayRecorder.xcodeproj'})
for target, name, app in ((app_target, 'MetaRayRecorder', True),(tests_target, 'MetaRayRecorderTests', False)):
    ent = ET.SubElement(entries, 'BuildActionEntry', {'buildForTesting':'YES','buildForRunning':'YES' if app else 'NO',
        'buildForProfiling':'YES' if app else 'NO','buildForArchiving':'YES' if app else 'NO','buildForAnalyzing':'YES'})
    ref(ent, target, name)
ta = ET.SubElement(scheme, 'TestAction', {'buildConfiguration':'Debug', 'selectedDebuggerIdentifier':'Xcode.DebuggerFoundation.Debugger.LLDB',
    'selectedLauncherIdentifier':'Xcode.IDEFoundation.Launcher.LLDB', 'shouldUseLaunchSchemeArgsEnv':'YES'})
testables = ET.SubElement(ta, 'Testables'); testable = ET.SubElement(testables, 'TestableReference', {'skipped':'NO'})
ref(testable, tests_target, 'MetaRayRecorderTests')
la = ET.SubElement(scheme, 'LaunchAction', {'buildConfiguration':'Debug','selectedDebuggerIdentifier':'Xcode.DebuggerFoundation.Debugger.LLDB',
    'selectedLauncherIdentifier':'Xcode.IDEFoundation.Launcher.LLDB','launchStyle':'0','useCustomWorkingDirectory':'NO',
    'ignoresPersistentStateOnLaunch':'NO','debugDocumentVersioning':'YES','debugServiceExtension':'internal','allowLocationSimulation':'YES'})
ref(ET.SubElement(la, 'BuildableProductRunnable', {'runnableDebuggingMode':'0'}), app_target, 'MetaRayRecorder')
pa = ET.SubElement(scheme, 'ProfileAction', {'buildConfiguration':'Release','shouldUseLaunchSchemeArgsEnv':'YES','savedToolIdentifier':'',
    'useCustomWorkingDirectory':'NO','debugDocumentVersioning':'YES'})
ref(ET.SubElement(pa,'BuildableProductRunnable',{'runnableDebuggingMode':'0'}), app_target, 'MetaRayRecorder')
ET.SubElement(scheme,'AnalyzeAction',{'buildConfiguration':'Debug'})
ET.SubElement(scheme,'ArchiveAction',{'buildConfiguration':'Release','revealArchiveInOrganizer':'YES'})
ET.indent(scheme)
ET.ElementTree(scheme).write(schemes/'MetaRayRecorder.xcscheme', encoding='UTF-8', xml_declaration=True)

info = dict(CFBundleDevelopmentRegion='fr', CFBundleDisplayName='MetaRay Recorder', CFBundleExecutable='$(EXECUTABLE_NAME)',
    CFBundleIdentifier='$(PRODUCT_BUNDLE_IDENTIFIER)', CFBundleInfoDictionaryVersion='6.0', CFBundleName='MetaRayRecorder',
    CFBundlePackageType='APPL', CFBundleShortVersionString='$(MARKETING_VERSION)', CFBundleVersion='$(CURRENT_PROJECT_VERSION)',
    CFBundleURLTypes=[dict(CFBundleTypeRole='Editor', CFBundleURLName='$(PRODUCT_BUNDLE_IDENTIFIER)', CFBundleURLSchemes=['metarayrecorder'])],
    MWDAT=dict(AppLinkURLScheme='metarayrecorder://', MetaAppID='', ClientToken='', TeamID='',
               Analytics=dict(OptOut=True), CrashReporting=dict(OptOut=True)),
    UIBackgroundModes=['processing','bluetooth-central','bluetooth-peripheral','external-accessory','audio'],
    UISupportedExternalAccessoryProtocols=['com.meta.ar.wearable'],
    NSBluetoothAlwaysUsageDescription='Relier vos Ray-Ban Meta et recevoir leur flux vidéo.',
    NSBluetoothPeripheralUsageDescription='Communiquer avec vos Ray-Ban Meta.',
    NSLocalNetworkUsageDescription='Permettre les échanges locaux entre votre iPhone et vos lunettes.',
    NSBonjourServices=['_bonjour._tcp'],
    NSMicrophoneUsageDescription='Enregistrer le son du microphone Bluetooth sélectionné dans vos vidéos.',
    NSPhotoLibraryAddUsageDescription='Ajouter à Photos les vidéos que vous choisissez d’exporter.',
    UIApplicationSceneManifest=dict(UIApplicationSupportsMultipleScenes=False),
    UILaunchScreen={}, UIRequiredDeviceCapabilities=['arm64'],
    UISupportedInterfaceOrientations=['UIInterfaceOrientationPortrait'],
    UIFileSharingEnabled=True, LSSupportsOpeningDocumentsInPlace=True,
    ITSAppUsesNonExemptEncryption=False)
with (ROOT/'MetaRayRecorder/Resources/Info.plist').open('wb') as fp: plistlib.dump(info, fp, sort_keys=False)
print(f'Generated {PROJECT.name}: {len(app_sources)} application source files + XCTest target; Meta DAT exact 1.0.0.')

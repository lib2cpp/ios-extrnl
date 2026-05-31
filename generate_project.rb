require 'xcodeproj'

PROJECT_NAME = 'ChessBot'
BUNDLE_ID    = 'com.chessbot.app'
EXT_BUNDLE   = 'com.chessbot.app.extension'

proj = Xcodeproj::Project.new("#{PROJECT_NAME}.xcodeproj")

# ── Главное приложение ──────────────────────────────────
app_target = proj.new_target(:application, PROJECT_NAME, :ios, '15.0')
app_group  = proj.main_group.new_group(PROJECT_NAME)

# AppDelegate.swift
app_delegate = app_group.new_file('AppDelegate.swift')
app_target.add_file_references([app_delegate])

File.write('AppDelegate.swift', <<~SWIFT)
  import UIKit
  @main
  class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication,
      didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
      window = UIWindow(frame: UIScreen.main.bounds)
      let vc = UIViewController()
      vc.view.backgroundColor = .black
      let label = UILabel()
      label.text = "Chess Bot\nОткрой Safari → chess.com"
      label.textColor = UIColor(red:0.78,green:0.63,blue:0.13,alpha:1)
      label.font = UIFont(name:"Courier New", size:16) ?? .systemFont(ofSize:16)
      label.numberOfLines = 0
      label.textAlignment = .center
      label.translatesAutoresizingMaskIntoConstraints = false
      vc.view.addSubview(label)
      NSLayoutConstraint.activate([
        label.centerXAnchor.constraint(equalTo:vc.view.centerXAnchor),
        label.centerYAnchor.constraint(equalTo:vc.view.centerYAnchor),
        label.widthAnchor.constraint(equalTo:vc.view.widthAnchor, multiplier:0.8)
      ])
      window?.rootViewController = vc
      window?.makeKeyAndVisible()
      return true
    }
  }
SWIFT

# Info.plist для приложения
app_plist = app_group.new_file('Info.plist')
app_target.add_file_references([app_plist])

File.write('Info.plist', <<~XML)
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0"><dict>
    <key>CFBundleIdentifier</key><string>#{BUNDLE_ID}</string>
    <key>CFBundleName</key><string>Chess Bot</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSRequiresIPhoneOS</key><true/>
    <key>NSExtension</key><dict>
      <key>NSExtensionPointIdentifier</key>
      <string>com.apple.Safari.web-extension</string>
    </dict>
    <key>UILaunchStoryboardName</key><string>LaunchScreen</string>
    <key>UISupportedInterfaceOrientations</key>
    <array><string>UIInterfaceOrientationPortrait</string></array>
  </dict></plist>
XML

# ── Расширение ──────────────────────────────────────────
ext_target = proj.new_target(:app_extension, "#{PROJECT_NAME} Extension", :ios, '15.0')
ext_group  = proj.main_group.new_group("#{PROJECT_NAME} Extension")

# SafariWebExtensionHandler.swift
handler_file = ext_group.new_file('SafariWebExtensionHandler.swift')
ext_target.add_file_references([handler_file])

File.write('SafariWebExtensionHandler.swift', <<~SWIFT)
  import SafariServices
  import os.log
  class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
      let item = context.inputItems[0] as! NSExtensionItem
      let message = item.userInfo?[SFExtensionMessageKey]
      os_log(.default, "Chess Bot received: %@", message as! CVarArg)
      let resp = NSExtensionItem()
      resp.userInfo = [SFExtensionMessageKey: ["status": "ok"]]
      context.completeRequest(returningItems: [resp], completionHandler: nil)
    }
  }
SWIFT

# Info.plist расширения
ext_plist = ext_group.new_file('ExtInfo.plist')
ext_target.add_file_references([ext_plist])

File.write('ExtInfo.plist', <<~XML)
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0"><dict>
    <key>CFBundleIdentifier</key><string>#{EXT_BUNDLE}</string>
    <key>CFBundleName</key><string>Chess Bot Extension</string>
    <key>CFBundlePackageType</key><string>XPC!</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>NSExtension</key><dict>
      <key>NSExtensionPointIdentifier</key>
      <string>com.apple.Safari.web-extension</string>
      <key>NSExtensionPrincipalClass</key>
      <string>$(PRODUCT_MODULE_NAME).SafariWebExtensionHandler</string>
    </dict>
  </dict></plist>
XML

# Resources группа
res_group = ext_group.new_group('Resources')
['manifest.json','content.js','background.js','popup.html'].each do |f|
  ref = res_group.new_file("ChessBot Extension/Resources/#{f}")
  ext_target.add_file_references([ref])
end

# ── Build settings ──────────────────────────────────────
[app_target, ext_target].each do |t|
  t.build_configurations.each do |c|
    c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
    c.build_settings['SWIFT_VERSION']              = '5.0'
    c.build_settings['CODE_SIGN_IDENTITY']         = ''
    c.build_settings['CODE_SIGNING_REQUIRED']      = 'NO'
    c.build_settings['CODE_SIGNING_ALLOWED']       = 'NO'
  end
end

app_target.build_configurations.each do |c|
  c.build_settings['INFOPLIST_FILE']    = 'Info.plist'
  c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = BUNDLE_ID
end

ext_target.build_configurations.each do |c|
  c.build_settings['INFOPLIST_FILE']    = 'ExtInfo.plist'
  c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = EXT_BUNDLE
end

# Embed extension в приложение
embed = app_target.new_copy_files_build_phase('Embed App Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
embed.add_file_reference(ext_target.product_reference)

proj.save
puts "✓ ChessBot.xcodeproj создан"

require 'xcodeproj'

PROJECT_NAME = 'ChessBot'
BUNDLE_ID    = 'com.chessbot.app'
EXT_BUNDLE   = 'com.chessbot.app.extension'

proj = Xcodeproj::Project.new("#{PROJECT_NAME}.xcodeproj")

# ── AppDelegate.swift ───────────────────────────────────
File.write('AppDelegate.swift', <<~SWIFT)
  import UIKit
  @main
  class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication,
      didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
      window = UIWindow(frame: UIScreen.main.bounds)
      let vc = UIViewController()
      vc.view.backgroundColor = UIColor(red:0.06,green:0.06,blue:0.06,alpha:1)
      let label = UILabel()
      label.text = "♛ Chess Bot\\n\\nОткрой Safari → chess.com\\nНажми иконку расширения в адресной строке"
      label.textColor = UIColor(red:0.78,green:0.63,blue:0.13,alpha:1)
      label.font = UIFont(name:"Courier New", size:15) ?? .systemFont(ofSize:15)
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

# ── SafariWebExtensionHandler.swift ────────────────────
File.write('SafariWebExtensionHandler.swift', <<~SWIFT)
  import SafariServices
  import os.log
  class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
      let item = context.inputItems[0] as! NSExtensionItem
      let message = item.userInfo?[SFExtensionMessageKey]
      os_log(.default, "Chess Bot: %@", message as! CVarArg)
      let resp = NSExtensionItem()
      resp.userInfo = [SFExtensionMessageKey: ["status": "ok"]]
      context.completeRequest(returningItems: [resp], completionHandler: nil)
    }
  }
SWIFT

# ── Info.plist (приложение) ─────────────────────────────
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
    <key>UISupportedInterfaceOrientations</key>
    <array><string>UIInterfaceOrientationPortrait</string></array>
  </dict></plist>
XML

# ── ExtInfo.plist (расширение) ──────────────────────────
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

# ══════════════════════════════════════════════════════
# Главное приложение
# ══════════════════════════════════════════════════════
app_target = proj.new_target(:application, PROJECT_NAME, :ios, '15.0')
app_group  = proj.main_group.new_group(PROJECT_NAME)

# ТОЛЬКО swift-файлы в Compile Sources
app_delegate_ref = app_group.new_file('AppDelegate.swift')
app_target.source_build_phase.add_file_reference(app_delegate_ref)

# Info.plist — НЕ добавляем в какие-либо build phases, только ссылка
app_plist_ref = app_group.new_file('Info.plist')
# (не вызываем add_file_reference — plist подтягивается через INFOPLIST_FILE)

# ══════════════════════════════════════════════════════
# Расширение
# ══════════════════════════════════════════════════════
ext_target = proj.new_target(:app_extension, "#{PROJECT_NAME} Extension", :ios, '15.0')
ext_group  = proj.main_group.new_group("#{PROJECT_NAME} Extension")

# ТОЛЬКО handler в Compile Sources расширения
handler_ref = ext_group.new_file('SafariWebExtensionHandler.swift')
ext_target.source_build_phase.add_file_reference(handler_ref)

# ExtInfo.plist — только ссылка
ext_plist_ref = ext_group.new_file('ExtInfo.plist')

# Resources группа — добавляем в Copy Bundle Resources (НЕ в compile sources)
res_group = ext_group.new_group('Resources')
resource_files = ['manifest.json', 'content.js', 'background.js', 'popup.html']

resource_files.each do |f|
  src  = "ChessBotExtension/Resources/#{f}"
  dest = "ChessBot Extension/Resources/#{f}"
  # Убедимся что файл существует в нужном месте
  FileUtils.mkdir_p(File.dirname(dest))
  FileUtils.cp(src, dest) if File.exist?(src) && !File.exist?(dest)

  ref = res_group.new_file(dest)
  # Добавляем в Resources build phase (copy bundle resources)
  ext_target.resources_build_phase.add_file_reference(ref)
end

# ══════════════════════════════════════════════════════
# Build Settings
# ══════════════════════════════════════════════════════
[app_target, ext_target].each do |t|
  t.build_configurations.each do |c|
    c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
    c.build_settings['SWIFT_VERSION']              = '5.0'
    c.build_settings['CODE_SIGN_IDENTITY']         = ''
    c.build_settings['CODE_SIGNING_REQUIRED']      = 'NO'
    c.build_settings['CODE_SIGNING_ALLOWED']       = 'NO'
    c.build_settings['SKIP_INSTALL']               = 'NO'
  end
end

app_target.build_configurations.each do |c|
  c.build_settings['INFOPLIST_FILE']              = 'Info.plist'
  c.build_settings['PRODUCT_BUNDLE_IDENTIFIER']   = BUNDLE_ID
  c.build_settings['PRODUCT_NAME']                = PROJECT_NAME
end

ext_target.build_configurations.each do |c|
  c.build_settings['INFOPLIST_FILE']              = 'ExtInfo.plist'
  c.build_settings['PRODUCT_BUNDLE_IDENTIFIER']   = EXT_BUNDLE
  c.build_settings['PRODUCT_NAME']                = "#{PROJECT_NAME} Extension"
end

# ══════════════════════════════════════════════════════
# Embed extension в приложение
# ══════════════════════════════════════════════════════
embed_phase = app_target.new_copy_files_build_phase('Embed App Extensions')
embed_phase.symbol_dst_subfolder_spec = :plug_ins
embed_ref = embed_phase.add_file_reference(ext_target.product_reference)
embed_ref.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

proj.save
puts "✓ ChessBot.xcodeproj создан успешно"

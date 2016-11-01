/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

#if !NO_FABRIC
    import Crashlytics
#endif
import Shared
import MessageUI

let kPrefKeyNoScriptOn = "noscript_on"
let kPrefKeyFingerprintProtection = "fingerprintprotection_on"
let kPrefKeyPrivateBrowsingAlwaysOn = "privateBrowsingAlwaysOn"

class BraveSettingsView : AppSettingsTableViewController {

    static var cachedIs3rdPartyPasswordManagerInstalled = false

    var debugToggleItemToTriggerCrashCount = 0

    override func tableView(tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        let footerView = InsetLabel(frame: CGRectMake(0, 0, tableView.frame.size.width, 40))
        footerView.leftInset = CGFloat(20)
        footerView.rightInset = CGFloat(10)
        footerView.numberOfLines = 0
        footerView.font = UIFont.boldSystemFontOfSize(13)
        return footerView
    }

    override func tableView(tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 0
    }

    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }

    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)

        if BraveApp.getPrefs()?.boolForKey(kPrefKeyFingerprintProtection) ?? false {
            if let tab = getApp().tabManager.selectedTab where tab.getHelper(FingerprintingProtection.self) == nil {
                let fp = FingerprintingProtection(browser: tab)
                tab.addHelper(fp)
            }
        }
    }

    override func generateSettings() -> [SettingSection] {
        let prefs = profile.prefs
        var generalSettings = [
            SearchSetting(settings: self),
            BoolSetting(prefs: prefs, prefKey: "saveLogins", defaultValue: true, titleText: Strings.Save_Logins, statusText: nil, settingDidChange:  { value in
                                // Hidden way to trigger a crash for testing
                if (self.debugToggleItemToTriggerCrashCount > 4) {
                    UIAlertView(title: "Trigger a crash for testing", message: "Force a crash?", delegate: self, cancelButtonTitle: "Cancel", otherButtonTitles: "OK").show()
                    self.debugToggleItemToTriggerCrashCount = 0
                } else {
                    self.debugToggleItemToTriggerCrashCount += 1
                }
            })
            ,BoolSetting(prefs: prefs, prefKey: "blockPopups", defaultValue: true,
                titleText: Strings.Block_Popups)
        ]

        if UIDevice.currentDevice().userInterfaceIdiom == .Pad {
            generalSettings.append(BoolSetting(prefs: prefs, prefKey: kPrefKeyTabsBarShowPolicy, defaultValue: true,
                titleText: Strings.Show_Tabs_Bar, statusText: nil,
                settingDidChange: { value in
                    getApp().browserViewController.urlBar.updateTabsBarShowing()
                }
            ))
        } else {
            generalSettings.append(TabsBarIPhoneSetting(profile: self.profile))
        }


        if BraveSettingsView.cachedIs3rdPartyPasswordManagerInstalled {
            generalSettings.append(PasswordManagerButtonSetting(profile: self.profile))
        }

        BraveApp.is3rdPartyPasswordManagerInstalled(refreshLookup: true).upon {
            result in
            if result == BraveSettingsView.cachedIs3rdPartyPasswordManagerInstalled {
                return
            }
            BraveSettingsView.cachedIs3rdPartyPasswordManagerInstalled = result

            // TODO: if PW manager is removed, settings must be opening a 2nd time for setting to disappear.
            if result {
                postAsyncToMain(0) { // move from db thread back to main
                    generalSettings.append(PasswordManagerButtonSetting(profile: self.profile))
                    self.settings[0] = SettingSection(title: NSAttributedString(string: Strings.General), children: generalSettings)
                    let range = NSMakeRange(0, 1)
                    let section = NSIndexSet(indexesInRange: range)
                    self.tableView.reloadSections(section, withRowAnimation: .Automatic)
                }
            }
        }


        settings += [
            SettingSection(title: NSAttributedString(string: Strings.General), children: generalSettings),
            SettingSection(title: NSAttributedString(string: Strings.Privacy), children:
                [ClearPrivateDataSetting(settings: self), CookieSetting(profile: self.profile),
                    BoolSetting(prefs: prefs, prefKey: kPrefKeyPrivateBrowsingAlwaysOn, defaultValue: false, titleText: Strings.Private_Browsing_Only, statusText: nil, settingDidChange: { isOn in
                        if !isOn {
                            return
                        }
                        if !PrivateBrowsing.singleton.isOn {
                            getApp().browserViewController.switchToPrivacyMode()
                            getApp().tabManager.addTabAndSelect(isPrivate: true)
                        }
                    })]
            ),
            SettingSection(title: NSAttributedString(string: Strings.Brave_Shield_Defaults), children:
                [BoolSetting(prefs: prefs, prefKey: AdBlocker.prefKey, defaultValue: true, titleText: Strings.Block_Ads_and_Tracking),
                    BoolSetting(prefs: prefs, prefKey: HttpsEverywhere.prefKey, defaultValue: true, titleText: Strings.HTTPS_Everywhere),
                    BoolSetting(prefs: prefs, prefKey: SafeBrowsing.prefKey, defaultValue: true, titleText: Strings.Block_Phishing_and_Malware),
                    BoolSetting(prefs: prefs, prefKey: kPrefKeyNoScriptOn, defaultValue: false, titleText: Strings.Block_Scripts),
                    BoolSetting(prefs: prefs, prefKey: kPrefKeyFingerprintProtection, defaultValue: false, titleText: Strings.Fingerprinting_Protection)
                ])]

        //#if !DISABLE_INTRO_SCREEN
        settings += [
            SettingSection(title: NSAttributedString(string: Strings.Support), children: [
                // TODO: GROWTH: BoolSetting(prefs: prefs, prefKey: BraveUX.PrefKeyUserAllowsTelemetry, defaultValue: true, titleText: Strings.Allow_Brave_to_send_info_to_improve_our_app, comment: "option in settings screen")),
                ShowIntroductionSetting(settings: self),
                BraveSupportLinkSetting(parentVC: self),
                BravePrivacyPolicySetting(), BraveTermsOfUseSetting(),
                ])]
        //#endif
        settings += [
            SettingSection(title: NSAttributedString(string: Strings.About), children: [
                VersionSetting(settings: self),
                ])
        ]
        return settings
    }
}

extension BraveSettingsView : UIAlertViewDelegate {
    func alertView(alertView: UIAlertView, didDismissWithButtonIndex buttonIndex: Int) {
        if buttonIndex == alertView.cancelButtonIndex {
            return
        }
        #if !NO_FABRIC
            Crashlytics.sharedInstance().crash()
        #endif
    }
}

class VersionSetting : Setting {
    let settings: SettingsTableViewController

    init(settings: SettingsTableViewController) {
        self.settings = settings
        super.init(title: nil)
    }

    override var title: NSAttributedString? {
        let appVersion = NSBundle.mainBundle().objectForInfoDictionaryKey("CFBundleShortVersionString") as! String
        let buildNumber = NSBundle.mainBundle().objectForInfoDictionaryKey("CFBundleVersion") as! String
        return NSAttributedString(string: String(format: Strings.Version_template, appVersion, buildNumber), attributes: [NSForegroundColorAttributeName: UIConstants.TableViewRowTextColor])
    }

    override func onConfigureCell(cell: UITableViewCell) {
        super.onConfigureCell(cell)
        cell.selectionStyle = .None
    }
}


// Opens the search settings pane
class PasswordManagerButtonSetting: PicklistSettingMainItem<String> {

    static var currentSetting: ThirdPartyPasswordManagerType?

    private static let _prefName = kPrefName3rdPartyPasswordShortcutEnabled
    private static let _options =  [
        Choice<String> { PasswordManagerButtonAction.ShowPicker },
        Choice<String> { PasswordManagerButtonAction.OnePassword },
        Choice<String> { PasswordManagerButtonAction.LastPass }
    ]

    static func setupOnAppStart() {
        guard let current = BraveApp.getPrefs()?.intForKey(_prefName) else { return }
        switch Int(current) {
        case PasswordManagerButtonAction.OnePassword.prefId:
            currentSetting = PasswordManagerButtonAction.OnePassword
        case PasswordManagerButtonAction.LastPass.prefId:
            currentSetting = PasswordManagerButtonAction.LastPass
        default:
            currentSetting = PasswordManagerButtonAction.ShowPicker
        }
    }

    init(profile: Profile) {
        super.init(profile: profile, displayName: "", prefName: PasswordManagerButtonSetting._prefName, options: PasswordManagerButtonSetting._options)
        picklistFooterMessage = Strings.Password_manager_button_settings_footer
    }

    override func picklistSetting(setting: PicklistSettingOptionsView, pickedOptionId: Int) {
        super.picklistSetting(setting, pickedOptionId: pickedOptionId)
        PasswordManagerButtonSetting.setupOnAppStart()
    }

    override var title: NSAttributedString? {
        return NSAttributedString(string: Strings.Password_manager_button, attributes: [NSForegroundColorAttributeName: UIConstants.TableViewRowTextColor, NSFontAttributeName: UIFont.systemFontOfSize(14)])
    }
}


// Opens the search settings pane
class CookieSetting: PicklistSettingMainItem<UInt> {
    private static let _prefName = "braveAcceptCookiesPref"
    private static let _options =  [
        Choice<UInt> { (displayName: Strings.Block_3rd_party_cookies, object: UInt(NSHTTPCookieAcceptPolicy.OnlyFromMainDocumentDomain.rawValue), optionId: 0) },
        Choice<UInt> { (displayName: Strings.Block_all_cookies, object: UInt(NSHTTPCookieAcceptPolicy.Never.rawValue), optionId: 1) },
        Choice<UInt> { (displayName: Strings.Dont_block_cookies, object: UInt( NSHTTPCookieAcceptPolicy.Always.rawValue), optionId: 2) }
    ]

    static func setPolicyFromOptionId(optionId: Int) {
        for option in _options {
            if option.item().optionId == optionId {
                NSHTTPCookieStorage.sharedHTTPCookieStorage().cookieAcceptPolicy = NSHTTPCookieAcceptPolicy.init(rawValue: option.item().object)!
            }
        }
    }

    static func setupOnAppStart() {
        let current = BraveApp.getPrefs()?.intForKey(_prefName) ?? 0
        setPolicyFromOptionId(Int(current))
    }

    init(profile: Profile) {
        super.init(profile: profile, displayName: Strings.Cookie_Control, prefName: CookieSetting._prefName, options: CookieSetting._options)
    }

    override func picklistSetting(setting: PicklistSettingOptionsView, pickedOptionId: Int) {
        super.picklistSetting(setting, pickedOptionId: pickedOptionId)
        CookieSetting.setPolicyFromOptionId(pickedOptionId)
    }
}

// Opens the search settings pane
class TabsBarIPhoneSetting: PicklistSettingMainItem<Int> {
    private static func getOptions() -> [Choice<Int>] {
        let opt = [
            Choice<Int> { (displayName: Strings.Never_show, object: TabsBarShowPolicy.Never.rawValue, optionId: 0) },
            Choice<Int> { (displayName: Strings.Always_show, object: TabsBarShowPolicy.Always.rawValue, optionId: 1) },
            Choice<Int> { (displayName: Strings.Show_in_landscape_only, object: TabsBarShowPolicy.LandscapeOnly.rawValue, optionId: 2) }
        ]
        return opt

    }

    init(profile: Profile) {
        super.init(profile: profile, displayName: Strings.Show_Tabs_Bar, prefName: kPrefKeyTabsBarShowPolicy, options: TabsBarIPhoneSetting.getOptions())
    }

    override func picklistSetting(setting: PicklistSettingOptionsView, pickedOptionId: Int) {
        super.picklistSetting(setting, pickedOptionId: pickedOptionId)
        getApp().browserViewController.urlBar.updateTabsBarShowing()
    }

    override func getCurrent() -> Int {
        return Int(BraveApp.getPrefs()?.intForKey(prefName) ?? Int32(kPrefKeyTabsBarOnDefaultValue.rawValue))
    }
}




// Clear all stored passwords. This will clear SQLite storage and the system shared credential storage.
class PasswordsClearable: Clearable {
    let profile: Profile
    init(profile: Profile) {
        self.profile = profile
    }

    var label: String {
        return Strings.Saved_Logins
    }

    func clear() -> Success {
        // Clear our storage
        return profile.logins.removeAll() >>== { res in
            let storage = NSURLCredentialStorage.sharedCredentialStorage()
            let credentials = storage.allCredentials
            for (space, credentials) in credentials {
                for (_, credential) in credentials {
                    storage.removeCredential(credential, forProtectionSpace: space)
                }
            }
            return succeed()
        }
    }
}

class BraveSupportLinkSetting: Setting, MFMailComposeViewControllerDelegate {
    let parentViewController:UIViewController
    
    init(parentVC:UIViewController) {
        parentViewController = parentVC
    }

    override var title: NSAttributedString? {
        return NSAttributedString(string: Strings.Report_a_bug, attributes: [NSForegroundColorAttributeName: UIConstants.TableViewRowTextColor])
    }
    
    func mailComposeController(controller: MFMailComposeViewController, didFinishWithResult result: MFMailComposeResult, error: NSError?) {
        
        controller.dismissViewControllerAnimated(true) {
            if result == MFMailComposeResult.Saved || result == MFMailComposeResult.Sent {
                //only show 'thanks' dialog when Saved/Sent.
                //TODO turn this into a Toast-type notification that goes away by itself.
                let sendFeedbackThanks = UIAlertView(title: "Thanks!", message: "Thank you for your feedback!", delegate: self, cancelButtonTitle: "OK")
                sendFeedbackThanks.show()
            } else if result == MFMailComposeResult.Failed {
                self.showMailErrorDialog()
            }
        }
    }

    override func onClick(navigationController: UINavigationController?) {
        //MFMailComposeViewController is wonky on simulator, detect & avoid
        let isDevice = (TARGET_OS_SIMULATOR == 0)
        
        if MFMailComposeViewController.canSendMail() && isDevice {
            
            let reportBugMailAddress = "support+ios@brave.com"
            let reportBugMailSubject = Strings.Brave_for_iOS_Feedback
            let reportBugMailBody = Strings.Email_Body

            
            let mailComposerVC = MFMailComposeViewController()
            mailComposerVC.mailComposeDelegate = self
            mailComposerVC.setToRecipients([reportBugMailAddress])
            mailComposerVC.setSubject(reportBugMailSubject)
            
            let iOSVersionLabel = "iOS version"
            let deviceLabel = "Device"
            let braveVersionLabel = "Brave version"
            
            let appVersionString: String = NSBundle.mainBundle().objectForInfoDictionaryKey("CFBundleShortVersionString") as! String
            let buildNumber: String = NSBundle.mainBundle().objectForInfoDictionaryKey("CFBundleVersion") as! String
            let versionAndBuildNumber: String = "\(appVersionString) (\(buildNumber))"
            
            var message = reportBugMailBody
            message += "\(iOSVersionLabel) [\(UIDevice.currentDevice().systemName)/\(UIDevice.currentDevice().systemVersion)]\n"
            message += "\(deviceLabel): [\(UIDevice.currentDevice().name)/\(UIDevice.currentDevice().model)]\n"
            message += "\(braveVersionLabel): [\(versionAndBuildNumber)]\n"
            message += "-----------------------------\n"
            mailComposerVC.setMessageBody(message, isHTML: false)
            
            parentViewController.presentViewController(mailComposerVC, animated: true, completion: nil)
        } else {
            showMailErrorDialog()
        }
    }
    
    func showMailErrorDialog() {
        let sendMailErrorAlert = UIAlertView(title: "Error sending email", message: "It appears you're not setup for email on this device.  Please check your email configuration and try again.", delegate: self, cancelButtonTitle: "OK")
        sendMailErrorAlert.show()
    }

    override func onConfigureCell(cell: UITableViewCell) {
        super.onConfigureCell(cell)
        let g = UILongPressGestureRecognizer(target: self, action: #selector(longPress))
        cell.addGestureRecognizer(g)
    }

    @objc func longPress(g: UILongPressGestureRecognizer) {
        if g.state != .Began {
            return
        }
        // Use this to experiment with fixing bug where page is partially rendered
        // TODO use this to add special debugging functions

        #if FLEX_ON
           FLEXManager.sharedManager().showExplorer()
        #endif
    }

}

class BravePrivacyPolicySetting: Setting {
    override var title: NSAttributedString? {
        return NSAttributedString(string: Strings.Privacy_Policy, attributes: [NSForegroundColorAttributeName: UIConstants.TableViewRowTextColor])
    }

    override var url: NSURL? {
        return BraveUX.BravePrivacyURL
    }

    override func onClick(navigationController: UINavigationController?) {
        setUpAndPushSettingsContentViewController(navigationController)
    }
}

class BraveTermsOfUseSetting: Setting {
    override var title: NSAttributedString? {
        return NSAttributedString(string: Strings.Terms_of_Use, attributes: [NSForegroundColorAttributeName: UIConstants.TableViewRowTextColor])
    }

    override var url: NSURL? {
        return NSURL(string: "https://www.brave.com/terms_of_use")
    }

    override func onClick(navigationController: UINavigationController?) {
        setUpAndPushSettingsContentViewController(navigationController)
    }
}




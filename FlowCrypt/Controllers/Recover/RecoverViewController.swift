//
// © 2017-2019 FlowCrypt Limited. All rights reserved.
//

import UIKit
import MBProgressHUD
import RealmSwift
import Promises

class RecoverViewController: BaseViewController, UITextFieldDelegate {

    @IBOutlet weak var passPhaseTextField: UITextField!
    @IBOutlet weak var btnLoadAccount: UIButton!
    @IBOutlet weak var scrollView: UIScrollView!
    
    var encryptedBackups: [KeyDetails]?

    override func viewDidLoad() {
        super.viewDidLoad()
        self.fetchBackups()
        self.setupTapGesture()
        passPhaseTextField.delegate = self
        registerKeyboardNotifications()
    }
    
    func registerKeyboardNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardWillShow(notification:)),
                                               name: UIResponder.keyboardWillShowNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardWillHide(notification:)),
                                               name: UIResponder.keyboardWillHideNotification,
                                               object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc func keyboardWillShow(notification: NSNotification) {
        let userInfo: NSDictionary = notification.userInfo! as NSDictionary
        let keyboardInfo = userInfo[UIResponder.keyboardFrameBeginUserInfoKey] as! NSValue
        let keyboardSize = keyboardInfo.cgRectValue.size
        let contentInsets = UIEdgeInsets(top: 0, left: 0, bottom: keyboardSize.height + 5, right: 0)
        scrollView.contentInset = contentInsets
        scrollView.scrollIndicatorInsets = contentInsets
    }
    
    @objc func keyboardWillHide(notification: NSNotification) {
        scrollView.contentInset = .zero
        scrollView.scrollIndicatorInsets = .zero
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.isNavigationBarHidden = true
        btnLoadAccount.layer.cornerRadius = 5
    }
    
    private func setupTapGesture() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(endEditing))
        tap.cancelsTouchesInView = false
        self.view.addGestureRecognizer(tap)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.view.endEditing(true)
        return true
    }
    
    func fetchBackups() {
        self.showSpinner()
        self.async({ () -> [KeyDetails] in
            let armoredBackupsData = try await(Imap.instance.searchBackups(email: GoogleApi.instance.getEmail()))
            let keyDetailsRes = try Core.parseKeys(armoredOrBinary: armoredBackupsData)
            return keyDetailsRes.keyDetails
        }, then: { keyDetails in
            self.hideSpinner()
            self.encryptedBackups = keyDetails.filter { $0.private != nil }
            if self.encryptedBackups!.count == 0 {
                self.showRetryFetchBackupsOrChangeAcctAlert(msg: Language.no_backups)
            }
        }, fail: { error in
            self.showRetryFetchBackupsOrChangeAcctAlert(msg: "\(Language.action_failed)\n\n\(error)")
        })
    }

    func showRetryFetchBackupsOrChangeAcctAlert(msg: String) {
        let alert = UIAlertController(title: "Notice", message: msg, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Retry", style: .default) { _ in self.fetchBackups() })
        alert.addAction(UIAlertAction(title: Language.use_other_account, style: .default) { _ in
            self.async({ try await(GoogleApi.instance.signOut()) }, then: { _ in
                let signInVc = self.instantiate(viewController: SignInViewController.self)
                self.navigationController?.pushViewController(signInVc, animated: true)
            })
        })
        self.present(alert, animated: true, completion: nil)
    }

    @IBAction func loadAccountButtonPressed(_ sender: Any) {
        let entered_pass_phrase = self.passPhaseTextField.text!
        if entered_pass_phrase.isEmpty {
            self.showErrAlert(Language.enter_pass_phrase) { self.passPhaseTextField.becomeFirstResponder() }
            return
        }
        self.showSpinner()
        self.async({ () -> [KeyDetails] in
            var matchingBackups = [KeyDetails]()
            for k in self.encryptedBackups! {
                let decryptRes = try Core.decryptKey(armoredPrv: k.private!, passphrase: entered_pass_phrase)
                if decryptRes.decryptedKey != nil {
                    matchingBackups.append(k)
                }
            }
            return matchingBackups
        }, then: { matchingBackups in
            guard matchingBackups.count > 0 else {
                self.showErrAlert(Language.wrong_pass_phrase_retry) { self.passPhaseTextField.becomeFirstResponder() }
                return
            }
            let realm = try! Realm()
            try! realm.write {
                for k in matchingBackups {
                    realm.add(KeyInfo(k, passphrase: entered_pass_phrase, source: "backup"))
                }
            }
            self.performSegue(withIdentifier: "InboxSegue", sender: nil)
        })
    }
    
    @objc
    private func endEditing() {
        self.view.endEditing(true)
    }
    
}

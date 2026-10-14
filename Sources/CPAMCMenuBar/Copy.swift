import Foundation
import QuotaCore

enum Copy {
    static var language: String { UserDefaults.standard.string(forKey: "language") ?? "auto" }
    static var isFrench: Bool {
        language == "fr" || (language == "auto" && (Locale.preferredLanguages.first ?? "en").hasPrefix("fr"))
    }
    static var locale: Locale { Locale(identifier: isFrench ? "fr_FR" : "en_US") }
    static func text(_ key: String) -> String { (isFrench ? fr[key] : en[key]) ?? en[key] ?? key }
    static func text(_ key: String, _ value: String) -> String { text(key).replacingOccurrences(of: "%@", with: value) }
    /// A branch Juice Bar can update from, by its name in Settings.
    static func branch(_ name: String) -> String { text(name + "Branch") }
    /// A pace, as it follows an amount left: “62% left, on track”.
    static func pace(_ pace: Pace) -> String { text("pace" + pace.rawValue.capitalized) }
    static let en = [
        "iconSettings": "Menu bar icon", "iconPreview": "Icon preview", "orientation": "Orientation",
        "vertical": "Vertical", "horizontal": "Horizontal", "iconAppearance": "Appearance",
        "color": "Color", "monochrome": "Black & white", "iconShows": "Bars show",
        "iconProviders": "OpenAI + Claude", "iconWindows": "Session + weekly", "provider": "Provider",
        "openai": "OpenAI", "claude": "Claude",
        "providersHint": "Each provider shows its best available account’s tighter session or weekly limit.",
        "combinedLeft": "left", "notReported": "not reported",
        "windowsHint": "OpenAI + Claude combined, out of 200% per bar. One best account per provider. If a reading is missing, the bar shows the known minimum (≥), not zero. This is not a token or credit balance.",
        "verticalOrder": "First bar on the left; second on the right.",
        "horizontalOrder": "First bar on top; second underneath.",
        "paceLegend": "Colors show the pace since each allowance renewed: green on track, orange on pace to run out before renewal, blue well under pace, red used up.",
        "monochromeLegend": "Black & white shows only what’s left; the icon’s tooltip tells the pace.",
        "paceOver": "on pace to run out before renewal", "paceSteady": "on track", "paceUnder": "well under pace",
        "paceOverLine": "At this pace, runs out in %@", "paceSteadyLine": "On track · about %@ used by renewal",
        "paceUnderLine": "Well under pace · about %@ used by renewal",
        "accountEnabled": "Use this account", "accountToggleHint": "Allow this account to handle new requests.",
        "accountUpdateFailed": "The change could not be confirmed. Refresh to check the current state.",
        "accountUpdating": "Updating…",
        "session": "Session", "weekly": "Weekly", "barLegend": "Session · Weekly",
        "launchAtLogin": "Launch at login", "loginApproval": "Allow in System Settings…",
        "loginError": "Could not update login settings. Check System Settings → Login Items.",
        "proxyStatus": "Proxy", "connected": "Connected", "notConnected": "Not connected",
        "serviceStopped": "Stopped", "start": "Start", "stop": "Stop",
        "stopNote": "Stopping disconnects agents using this proxy.",
        "serviceUnavailable": "Start/Stop is unavailable for this installation.",
        "serviceError": "Could not change the proxy service. Check its installation.",
        "test": "Test connection", "testing": "Testing…", "testPassed": "Connected — accounts readable",
        "testFailed": "Connection failed. Check the URL and key file.",
        "title": "Subscriptions", "back": "Back",
        "loading": "Reading your subscriptions…", "empty": "No Claude or Codex accounts connected",
        "limit": "Limit reached", "noReading": "No reading", "lastKnown": "Last known",
        "left": "% left", "ready": "ready", "disabled": "Disabled", "renews": "Renews",
        "cooldown": "Proxy cooldown until", "awaiting": "Awaiting a fresh reading",
        "refresh": "Refresh", "refreshing": "Refreshing…", "updated": "Updated",
        "dashboard": "Open CPAMC", "settings": "Settings…", "quit": "Quit Juice Bar",
        "five_hour": "Five-hour allowance", "seven_day": "Weekly allowance",
        "seven_day_opus": "Opus weekly allowance", "seven_day_sonnet": "Sonnet weekly allowance",
        "seven_day_oauth_apps": "OAuth apps weekly", "seven_day_cowork": "Cowork weekly",
        "primary": "Primary allowance", "secondary": "Secondary allowance",
        "extraOn": "Extra usage enabled", "extraOff": "Extra usage disabled",
        "credits": "Paid credits", "unlimited": "Unlimited", "resetGrant": "Unused promotional resets",
        "readOnly": "Read-only · No reset or billing actions", "connection": "Connection",
        "proxyURL": "Local proxy URL", "keyFile": "Management-key file", "choose": "Choose…",
        "save": "Save connection", "privacy": "Hide account names", "language": "Language",
        "auto": "System", "interval": "Provider reads every 5 minutes; local status every 30 seconds",
        "keyNote": "The key stays in its existing file. It is never copied into this app or sent outside your Mac.",
        "connecting": "Connecting…", "offline": "Proxy unavailable", "demo": "Demo · No accounts accessed",
        "lastChecked": "Provider checked", "unknownError": "Check the local connection in Settings.",
        "hideDisabled": "Hide disabled", "showDisabled": "Show disabled", "settingsTitle": "Settings", "general": "General",
        "updates": "Updates", "autoUpdate": "Update automatically", "checkNow": "Check now", "checking": "Checking…",
        "updateBranch": "Branch", "stableBranch": "Stable", "nightlyBranch": "Nightly",
        "upToDate": "Up to date", "updateAvailable": "Update available", "installUpdate": "Install",
        "installing": "Installing update…", "updateReady": "Ready, restarts when the menu closes", "restartNow": "Restart now",
        "devBuild": "Waiting for %@ to include this version",
        "modifiedBuild": "Built with local changes, not updated automatically",
        "unknownBuild": "Built without version information", "unsupportedLocation": "Updates need Juice Bar in an Applications folder",
        "noTools": "Install the Xcode Command Line Tools to update", "noBranch": "Nothing published on %@ yet",
        "downloadFailed": "Couldn’t reach GitHub. Trying again later.",
        "buildFailed": "The update couldn’t be built. Juice Bar keeps this version.",
        "installFailed": "The update couldn’t be installed.", "updateBusy": "Another update is in progress.",
        "updatesFooter": "Once a day, Juice Bar checks its branch on GitHub, then builds and installs new versions on this Mac. Stable gets releases; Nightly gets every change as soon as it’s merged.",
        "version": "Version", "lastCheckedAt": "Checked", "updateMenu": "Install update", "restartMenu": "Restart to update",
    ]
    static let fr = [
        "iconSettings": "Icône de la barre des menus", "iconPreview": "Aperçu de l’icône", "orientation": "Orientation",
        "vertical": "Verticale", "horizontal": "Horizontale", "iconAppearance": "Apparence",
        "color": "Couleur", "monochrome": "Noir et blanc", "iconShows": "Les barres indiquent",
        "iconProviders": "OpenAI + Claude", "iconWindows": "Session + semaine", "provider": "Fournisseur",
        "openai": "OpenAI", "claude": "Claude",
        "providersHint": "Chaque fournisseur indique le quota le plus contraignant, session ou semaine, de son meilleur compte disponible.",
        "combinedLeft": "restants", "notReported": "non communiqué",
        "windowsHint": "OpenAI + Claude cumulés, sur 200 % par barre. Un meilleur compte par fournisseur. Si une valeur manque, la barre indique le minimum connu (≥), pas zéro. Ce n’est pas un solde de tokens ou de crédits.",
        "verticalOrder": "Première barre à gauche, deuxième à droite.",
        "horizontalOrder": "Première barre en haut, deuxième en dessous.",
        "paceLegend": "Les couleurs indiquent le rythme depuis le renouvellement de chaque quota : vert dans le rythme, orange épuisé avant le renouvellement à ce rythme, bleu bien en dessous du rythme, rouge épuisé.",
        "monochromeLegend": "En noir et blanc, seul le niveau restant s’affiche ; l’infobulle de l’icône indique le rythme.",
        "paceOver": "épuisé avant le renouvellement à ce rythme", "paceSteady": "dans le rythme", "paceUnder": "bien en dessous du rythme",
        "paceOverLine": "À ce rythme, épuisé dans %@", "paceSteadyLine": "Dans le rythme · environ %@ utilisés d’ici le renouvellement",
        "paceUnderLine": "Bien en dessous du rythme · environ %@ utilisés d’ici le renouvellement",
        "accountEnabled": "Utiliser ce compte", "accountToggleHint": "Autoriser de nouvelles requêtes sur ce compte.",
        "accountUpdateFailed": "La modification n’a pas pu être confirmée. Actualise pour vérifier l’état actuel.",
        "accountUpdating": "Mise à jour…",
        "session": "Session", "weekly": "Semaine", "barLegend": "Session · Semaine",
        "launchAtLogin": "Lancer à l’ouverture de session", "loginApproval": "Autoriser dans les Réglages Système…",
        "loginError": "Impossible de modifier le démarrage. Vérifie Réglages Système → Ouverture.",
        "proxyStatus": "Proxy", "connected": "Connecté", "notConnected": "Non connecté",
        "serviceStopped": "Arrêté", "start": "Démarrer", "stop": "Arrêter",
        "stopNote": "L’arrêt déconnecte les agents qui utilisent ce proxy.",
        "serviceUnavailable": "Démarrer/Arrêter est indisponible pour cette installation.",
        "serviceError": "Impossible de modifier le service du proxy. Vérifie son installation.",
        "test": "Tester la connexion", "testing": "Test en cours…", "testPassed": "Connecté — comptes accessibles",
        "testFailed": "Connexion impossible. Vérifie l’adresse et le fichier de clé.",
        "title": "Abonnements", "back": "Retour",
        "loading": "Lecture de tes abonnements…", "empty": "Aucun compte Claude ou Codex connecté",
        "limit": "Limite atteinte", "noReading": "Aucune lecture", "lastKnown": "Dernière valeur",
        "left": "% restants", "ready": "disponibles", "disabled": "Désactivé", "renews": "Renouvellement",
        "cooldown": "Pause du proxy jusqu’au", "awaiting": "En attente d’une nouvelle lecture",
        "refresh": "Actualiser", "refreshing": "Actualisation…", "updated": "Actualisé à",
        "dashboard": "Ouvrir CPAMC", "settings": "Réglages…", "quit": "Quitter Juice Bar",
        "five_hour": "Quota sur cinq heures", "seven_day": "Quota hebdomadaire",
        "seven_day_opus": "Quota Opus hebdomadaire", "seven_day_sonnet": "Quota Sonnet hebdomadaire",
        "seven_day_oauth_apps": "Quota OAuth hebdomadaire", "seven_day_cowork": "Quota Cowork hebdomadaire",
        "primary": "Quota principal", "secondary": "Quota secondaire",
        "extraOn": "Usage supplémentaire activé", "extraOff": "Usage supplémentaire désactivé",
        "credits": "Crédits payants", "unlimited": "Illimités", "resetGrant": "Réinitialisations promotionnelles restantes",
        "readOnly": "Lecture seule · Aucun changement de quota ou de facturation", "connection": "Connexion",
        "proxyURL": "Adresse du proxy local", "keyFile": "Fichier de clé de gestion", "choose": "Choisir…",
        "save": "Enregistrer la connexion", "privacy": "Masquer les noms des comptes", "language": "Langue",
        "auto": "Système", "interval": "Quotas toutes les 5 minutes ; état local toutes les 30 secondes",
        "keyNote": "La clé reste dans son fichier actuel. Elle n’est ni copiée dans cette app ni envoyée hors de ton Mac.",
        "connecting": "Connexion…", "offline": "Proxy indisponible", "demo": "Démo · Aucun accès aux comptes",
        "lastChecked": "Quota vérifié à", "unknownError": "Vérifie la connexion locale dans les réglages.",
        "hideDisabled": "Masquer les désactivés", "showDisabled": "Afficher les désactivés", "settingsTitle": "Réglages", "general": "Général",
        "updates": "Mises à jour", "autoUpdate": "Mettre à jour automatiquement", "checkNow": "Vérifier", "checking": "Vérification…",
        "updateBranch": "Branche", "stableBranch": "Stable", "nightlyBranch": "Nightly",
        "upToDate": "À jour", "updateAvailable": "Mise à jour disponible", "installUpdate": "Installer",
        "installing": "Installation…", "updateReady": "Prête, redémarre à la fermeture du menu", "restartNow": "Redémarrer",
        "devBuild": "En attente de cette version sur %@",
        "modifiedBuild": "Compilée avec des modifications locales, pas de mise à jour automatique",
        "unknownBuild": "Compilée sans information de version", "unsupportedLocation": "Les mises à jour nécessitent Juice Bar dans un dossier Applications",
        "noTools": "Installe les Command Line Tools de Xcode pour mettre à jour", "noBranch": "Rien de publié sur %@ pour l’instant",
        "downloadFailed": "GitHub est injoignable. Nouvel essai plus tard.",
        "buildFailed": "La mise à jour n’a pas pu être compilée. Juice Bar garde cette version.",
        "installFailed": "La mise à jour n’a pas pu être installée.", "updateBusy": "Une autre mise à jour est en cours.",
        "updatesFooter": "Une fois par jour, Juice Bar vérifie sa branche sur GitHub, puis compile et installe les nouvelles versions sur ce Mac. Stable reçoit les versions publiées ; Nightly, chaque changement dès qu’il est intégré.",
        "version": "Version", "lastCheckedAt": "Vérifié à", "updateMenu": "Installer la mise à jour", "restartMenu": "Redémarrer pour mettre à jour",
    ]
    static func percent(_ left: Double?) -> String {
        guard let left else { return text("noReading") }
        return left <= 0 ? text("limit") : "\(Int(left.rounded()))\(text("left"))"
    }
    static func duration(_ date: Date?, now: Date) -> String? {
        guard let date, date > now else { return nil }
        let m = Int(ceil(date.timeIntervalSince(now) / 60))
        if m >= 1440 { return "\(m / 1440)\(isFrench ? "j" : "d") \((m % 1440) / 60)h" }
        if m >= 60 { return "\(m / 60)h \(m % 60)m" }
        return "\(m)m"
    }
    static func timestamp(_ date: Date, now: Date, includeDate: Bool = false) -> String {
        let f = DateFormatter(); f.locale = locale
        f.dateStyle = includeDate || !Calendar.current.isDate(date, inSameDayAs: now) ? .medium : .none
        f.timeStyle = .short
        return f.string(from: date)
    }
}

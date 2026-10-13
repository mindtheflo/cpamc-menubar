import Foundation

enum Copy {
    static var language: String { UserDefaults.standard.string(forKey: "language") ?? "auto" }
    static var isFrench: Bool {
        language == "fr" || (language == "auto" && (Locale.preferredLanguages.first ?? "en").hasPrefix("fr"))
    }
    static var locale: Locale { Locale(identifier: isFrench ? "fr_FR" : "en_US") }
    static func text(_ key: String) -> String { (isFrench ? fr[key] : en[key]) ?? en[key] ?? key }
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
        "title": "Subscriptions", "brand": "CPAMC · Made for Notis", "back": "Back",
        "loading": "Reading your subscriptions…", "empty": "No Claude or Codex accounts connected",
        "limit": "Limit reached", "noReading": "No reading", "lastKnown": "Last known",
        "left": "% left", "ready": "ready", "disabled": "Disabled", "renews": "Renews",
        "cooldown": "Proxy cooldown until", "awaiting": "Awaiting a fresh reading",
        "refresh": "Refresh", "refreshing": "Refreshing…", "updated": "Updated",
        "dashboard": "Open CPAMC", "settings": "Settings…", "quit": "Quit CPAMC Menu Bar",
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
        "title": "Abonnements", "brand": "CPAMC · Made for Notis", "back": "Retour",
        "loading": "Lecture de tes abonnements…", "empty": "Aucun compte Claude ou Codex connecté",
        "limit": "Limite atteinte", "noReading": "Aucune lecture", "lastKnown": "Dernière valeur",
        "left": "% restants", "ready": "disponibles", "disabled": "Désactivé", "renews": "Renouvellement",
        "cooldown": "Pause du proxy jusqu’au", "awaiting": "En attente d’une nouvelle lecture",
        "refresh": "Actualiser", "refreshing": "Actualisation…", "updated": "Actualisé à",
        "dashboard": "Ouvrir CPAMC", "settings": "Réglages…", "quit": "Quitter CPAMC Menu Bar",
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

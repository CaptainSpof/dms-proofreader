import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "proofreader"

    StringSetting {
        settingKey: "languageToolUrl"
        label: "URL LanguageTool"
        description: "Laisser vide pour la valeur par défaut de la machine (module Home Manager), sinon http://127.0.0.1:8081. L'API publique https://api.languagetool.org fonctionne aussi, avec des limites de débit."
        placeholder: "http://127.0.0.1:8081"
    }

    StringSetting {
        settingKey: "translateCommand"
        label: "Commande de traduction"
        description: "Laisser vide pour la valeur par défaut de la machine, sinon dms-translate dans le PATH. Doit accepter « SRC DST TEXTE » et « --pairs »."
        placeholder: "dms-translate"
    }

    StringSetting {
        settingKey: "pinnedLanguages"
        label: "Langues épinglées"
        description: "Codes LanguageTool séparés par des virgules, affichés en tête du menu dans cet ordre. Le bouton épingle à côté du menu modifie la même liste."
        placeholder: "fr, en-US, en-GB"
        defaultValue: "fr, en-US, en-GB"
    }

    ToggleSetting {
        settingKey: "autoCheck"
        label: "Vérification automatique"
        description: "Vérifier le texte pendant la frappe, après une courte pause. Sinon : bouton ou Ctrl+Entrée."
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "picky"
        label: "Mode exigeant"
        description: "Active les règles de style et de typographie supplémentaires de LanguageTool (level=picky)."
        defaultValue: false
    }

    SelectionSetting {
        settingKey: "motherTongue"
        label: "Langue maternelle"
        description: "Permet à LanguageTool de signaler les faux amis quand vous écrivez dans une autre langue."
        options: [
            {
                label: "Aucune",
                value: ""
            },
            {
                label: "Français",
                value: "fr"
            },
            {
                label: "English",
                value: "en-US"
            },
            {
                label: "Deutsch",
                value: "de-DE"
            },
            {
                label: "Español",
                value: "es"
            }
        ]
        defaultValue: "fr"
    }

    SelectionSetting {
        settingKey: "englishVariant"
        label: "Variante d'anglais"
        description: "Variante retenue quand la langue est détectée automatiquement."
        options: [
            {
                label: "English (US)",
                value: "en-US"
            },
            {
                label: "English (GB)",
                value: "en-GB"
            }
        ]
        defaultValue: "en-US"
    }
}

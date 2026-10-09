import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets as DCommon

// Slideout body. All state and the LanguageTool/translation calls live on the
// widget (`ctl`); this file only lays them out and drives the text area.
Item {
    id: panel

    required property var ctl
    required property var slideout

    // Set while the editor is being filled from `ctl`, so that load does not
    // echo back as an edit.
    property bool loading: false

    Keys.onEscapePressed: slideout.hide()

    // Only one slideout is visible at a time, so the editor pulls the shared
    // document when it is shown and pushes edits while it is the one in use.
    function onShown() {
        ctl.loadState();
        loading = true;
        textArea.text = ctl.html;
        loading = false;
        // Re-derive rather than trust the stored projection (older saves kept U+2028).
        if (ctl.text !== plainText())
            ctl.text = plainText();
        textArea.cursorPosition = textArea.length;
        if (ctl.languages.length === 0)
            ctl.fetchLanguages();
        if (!ctl.upToDate)
            ctl.runCheck();
        focusEditor();
    }

    // The layer surface only takes the keyboard once it is mapped, so focus
    // again once the slide-in has started rather than only at load time.
    function focusEditor() {
        textArea.forceActiveFocus();
        focusRetry.restart();
    }

    Timer {
        id: focusRetry
        interval: 120
        onTriggered: textArea.forceActiveFocus()
    }

    // Qt hands <br> back as U+2028 and paragraph breaks as U+2029. Swap both
    // for "\n" (one character for one, so match offsets still line up) before
    // the text reaches LanguageTool, translation or a plain-text copy.
    function plainText() {
        return textArea.getText(0, textArea.length).replace(/[\u2028\u2029]/g, "\n");
    }

    function toggleFormat(prop) {
        const f = textArea.cursorSelection.font;
        f[prop] = !f[prop];
        textArea.cursorSelection.font = f;
        textArea.forceActiveFocus();
    }

    function clearFormat() {
        const f = textArea.cursorSelection.font;
        f.bold = false;
        f.italic = false;
        f.underline = false;
        f.strikeout = false;
        textArea.cursorSelection.font = f;
        textArea.forceActiveFocus();
    }

    // Qt's own copy puts both text/html and text/plain on the clipboard, so
    // formatting survives into a mail or a document and a terminal still
    // gets plain text. Wayland only honours it right after an input event on
    // this surface, so check, and fall back to a plain-text copy (`dms cl`
    // offers a single MIME type) if it did not take.
    function copyFormatted() {
        const pos = textArea.cursorPosition;
        textArea.selectAll();
        textArea.copy();
        textArea.deselect();
        textArea.cursorPosition = pos;

        const wlPaste = ctl.machineDefaults.wlPasteBin || "wl-paste";
        Proc.runCommand("proofreader.verifyCopy", [wlPaste, "--list-types"], (stdout, exitCode) => {
            if (stdout.indexOf("text/html") >= 0) {
                ToastService.showInfo("Copié avec la mise en forme");
                return;
            }
            ctl.copy(ctl.text);
        }, 150, 3000);
    }


    Connections {
        target: panel.slideout
        function onRevealed() {
            panel.onShown();
        }
    }

    // Replace one match in place. remove()+insert() keeps the edit on the
    // undo stack, unlike assigning `text`.
    function applyReplacement(i, value) {
        const m = ctl.matches[i];
        if (!m || !ctl.upToDate)
            return;
        const end = m.offset + m.length;
        const delta = value.length - m.length;
        const newText = ctl.checkedText.slice(0, m.offset) + value + ctl.checkedText.slice(end);

        const rest = [];
        ctl.matches.forEach((o, j) => {
            if (j === i)
                return;
            if (o.offset >= end)
                rest.push(Object.assign({}, o, {
                    offset: o.offset + delta
                }));
            else if (o.offset + o.length <= m.offset)
                rest.push(o);
        });

        // Shift the bookkeeping first so the underlines survive the edit.
        ctl.checkedText = newText;
        ctl.matches = rest;
        ctl.activeIndex = -1;
        textArea.remove(m.offset, end);
        textArea.insert(m.offset, ctl.plainToHtml(value));
        textArea.cursorPosition = m.offset + value.length;
        textArea.forceActiveFocus();
    }

    function selectMatch(i) {
        const m = ctl.matches[i];
        if (!m || !ctl.upToDate)
            return;
        textArea.select(m.offset, m.offset + m.length);
        textArea.forceActiveFocus();
        ctl.activeIndex = i;
    }

    function replaceAll(value) {
        textArea.selectAll();
        textArea.remove(0, textArea.length);
        if (value)
            textArea.insert(0, ctl.plainToHtml(value));
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacingS

        // ── toolbar ──
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingS

            DankDropdown {
                id: languageDropdown
                dropdownWidth: 200
                enableFuzzySearch: true
                options: ["Auto (détection)"].concat(panel.ctl.languageList.map(l => l.name))
                // Pinned languages carry a pin in the menu (and in the trigger).
                optionIcons: ["auto_awesome"].concat(panel.ctl.languageList.map(l => panel.ctl.isPinned(l.longCode) ? "push_pin" : ""))
                currentValue: panel.ctl.language === "auto" ? "Auto (détection)" : panel.ctl.languageName(panel.ctl.language)
                onValueChanged: value => {
                    if (value === "Auto (détection)") {
                        panel.ctl.language = "auto";
                        return;
                    }
                    const hit = panel.ctl.languageList.find(l => l.name === value);
                    if (hit)
                        panel.ctl.language = hit.longCode;
                }
            }

            DankActionButton {
                readonly property bool pinned: panel.ctl.isPinned(panel.ctl.language)
                visible: panel.ctl.language !== "auto"
                iconName: "push_pin"
                iconFilled: pinned
                iconColor: pinned ? Theme.primary : Theme.surfaceVariantText
                tooltipText: pinned ? "Désépingler cette langue" : "Épingler cette langue en haut de la liste"
                onClicked: panel.ctl.togglePin(panel.ctl.language)
            }

            Item {
                Layout.fillWidth: true
            }

            DankActionButton {
                iconName: "spellcheck"
                tooltipText: "Vérifier (Ctrl+Entrée)"
                onClicked: panel.ctl.runCheck()
            }
            DankActionButton {
                iconName: "translate"
                visible: panel.ctl.translationAvailable
                iconColor: panel.ctl.showTranslation ? Theme.primary : Theme.surfaceVariantText
                tooltipText: "Traduction"
                onClicked: panel.ctl.showTranslation = !panel.ctl.showTranslation
            }
            DankActionButton {
                iconName: "content_copy"
                tooltipText: "Copier le texte (avec mise en forme)"
                onClicked: panel.copyFormatted()
            }
            DankActionButton {
                iconName: "delete_sweep"
                tooltipText: "Effacer"
                onClicked: panel.replaceAll("")
            }
        }

        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            font.pixelSize: Theme.fontSizeSmall
            color: panel.ctl.errorText ? Theme.error : Theme.surfaceVariantText
            text: {
                const c = panel.ctl;
                if (c.errorText)
                    return c.errorText;
                if (c.busy)
                    return "Vérification…";
                if (c.text.trim().length === 0)
                    return "Prêt.";
                if (!c.upToDate)
                    return "Modifié — en attente de vérification";
                const detected = c.langNames[c.baseCode(c.detectedCode)] || c.detectedName;
                const lang = c.language === "auto" && detected ? "Détecté : " + detected + " · " : "";
                const n = c.matches.length;
                return lang + (n === 0 ? "Aucune faute trouvée" : n + (n > 1 ? " problèmes" : " problème"));
            }
        }

        // ── formatting ──
        Row {
            spacing: Theme.spacingXS

            Repeater {
                model: [
                    {
                        icon: "format_bold",
                        prop: "bold",
                        tip: "Gras (Ctrl+B)"
                    },
                    {
                        icon: "format_italic",
                        prop: "italic",
                        tip: "Italique (Ctrl+I)"
                    },
                    {
                        icon: "format_underlined",
                        prop: "underline",
                        tip: "Souligné (Ctrl+U)"
                    },
                    {
                        icon: "strikethrough_s",
                        prop: "strikeout",
                        tip: "Barré"
                    }
                ]

                DankActionButton {
                    required property var modelData
                    iconName: modelData.icon
                    tooltipText: modelData.tip
                    readonly property bool active: textArea.cursorSelection.font[modelData.prop] === true
                    iconColor: active ? Theme.primary : Theme.surfaceVariantText
                    backgroundColor: active ? Theme.withAlpha(Theme.primary, 0.15) : "transparent"
                    onClicked: panel.toggleFormat(modelData.prop)
                }
            }

            DankActionButton {
                iconName: "format_clear"
                tooltipText: "Effacer la mise en forme"
                onClicked: panel.clearFormat()
            }
        }

        // ── editor ──
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 160
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh
            border.width: textArea.activeFocus ? 2 : 1
            border.color: textArea.activeFocus ? Theme.primary : Theme.outlineVariant

            Flickable {
                anchors.fill: parent
                // Clear the 2px focus border so it never covers the first line.
                anchors.margins: 2
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }

                TextArea.flickable: TextArea {
                    id: textArea

                    property var segments: []

                    font.family: SettingsData.fontFamily
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceText
                    selectedTextColor: Theme.background
                    selectionColor: Theme.primary
                    selectByMouse: true
                    wrapMode: TextArea.Wrap
                    textFormat: TextEdit.RichText
                    persistentSelection: true
                    padding: Theme.spacingM
                    topPadding: Theme.spacingL
                    background: null

                    // The style's default cursor is red; follow the text
                    // colour, as the DMS notepad does.
                    cursorDelegate: DCommon.DTextCursor {
                        width: 1.5
                        color: Theme.surfaceText
                        x: textArea.cursorRectangle.x
                        y: textArea.cursorRectangle.y
                        height: textArea.cursorRectangle.height
                        shown: textArea.cursorVisible

                        readonly property int areaCursorPosition: textArea.cursorPosition
                        onAreaCursorPositionChanged: resetBlink()
                    }

                    // TextArea's own placeholder does not render under the
                    // DMS style, so draw one.
                    StyledText {
                        x: textArea.leftPadding
                        y: textArea.topPadding
                        width: textArea.width - textArea.leftPadding - textArea.rightPadding
                        wrapMode: Text.WordWrap
                        visible: textArea.length === 0 && !textArea.preeditText
                        text: "Écrivez ou collez votre texte ici… (Ctrl+Entrée pour vérifier)"
                        font: textArea.font
                        color: Theme.surfaceTextSecondary
                    }

                    onTextChanged: {
                        segmentTimer.restart();
                        if (panel.loading)
                            return;
                        panel.ctl.html = text;
                        const plain = panel.plainText();
                        if (panel.ctl.text !== plain)
                            panel.ctl.text = plain;
                    }
                    onWidthChanged: segmentTimer.restart()
                    onContentHeightChanged: segmentTimer.restart()

                    onCursorPositionChanged: {
                        if (!panel.ctl.upToDate)
                            return;
                        const pos = cursorPosition;
                        const i = panel.ctl.matches.findIndex(m => pos >= m.offset && pos <= m.offset + m.length);
                        panel.ctl.activeIndex = i;
                        if (i >= 0)
                            matchList.positionViewAtIndex(i, ListView.Contain);
                    }

                    Keys.onPressed: event => {
                        if (!(event.modifiers & Qt.ControlModifier))
                            return;
                        switch (event.key) {
                        case Qt.Key_Return:
                        case Qt.Key_Enter:
                            panel.ctl.runCheck();
                            break;
                        case Qt.Key_B:
                            panel.toggleFormat("bold");
                            break;
                        case Qt.Key_I:
                            panel.toggleFormat("italic");
                            break;
                        case Qt.Key_U:
                            panel.toggleFormat("underline");
                            break;
                        default:
                            return;
                        }
                        event.accepted = true;
                    }

                    Connections {
                        target: panel.ctl
                        function onMatchesChanged() {
                            segmentTimer.restart();
                        }
                        function onCheckedTextChanged() {
                            segmentTimer.restart();
                        }
                    }

                    // Layout settles after text/width changes; measure on the
                    // next tick rather than inside the change handler.
                    Timer {
                        id: segmentTimer
                        interval: 16
                        onTriggered: textArea.segments = textArea.computeSegments()
                    }

                    // One underline per visual line a match covers, found by
                    // walking positions until the line's y changes.
                    function computeSegments() {
                        if (!panel.ctl.upToDate || panel.plainText() !== panel.ctl.checkedText)
                            return [];
                        const out = [];
                        panel.ctl.matches.forEach((m, i) => {
                            const start = m.offset;
                            const end = Math.min(m.offset + Math.max(m.length, 1), length);
                            let seg = positionToRectangle(start);
                            let right = seg.x;
                            const push = () => {
                                if (right - seg.x >= 1)
                                    out.push({
                                        x: seg.x,
                                        y: seg.y,
                                        w: right - seg.x,
                                        h: seg.height,
                                        index: i,
                                        color: panel.ctl.issueColor(m)
                                    });
                            };
                            for (let p = start + 1; p <= end; p++) {
                                const r = positionToRectangle(p);
                                if (Math.abs(r.y - seg.y) > 0.5) {
                                    push();
                                    seg = r;
                                }
                                right = r.x;
                            }
                            push();
                        });
                        return out;
                    }

                    Repeater {
                        model: textArea.segments

                        Item {
                            required property var modelData
                            x: modelData.x
                            y: modelData.y
                            width: modelData.w
                            height: modelData.h

                            Rectangle {
                                anchors.fill: parent
                                radius: 2
                                color: parent.modelData.color
                                opacity: parent.modelData.index === panel.ctl.activeIndex ? 0.18 : 0
                            }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 2
                                radius: 1
                                color: parent.modelData.color
                            }
                        }
                    }
                }
            }
        }

        // ── issues ──
        ListView {
            id: matchList
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, panel.height * 0.35)
            visible: panel.ctl.upToDate && panel.ctl.matches.length > 0
            clip: true
            spacing: Theme.spacingXS
            boundsBehavior: Flickable.StopAtBounds
            model: panel.ctl.upToDate ? panel.ctl.matches : []
            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            delegate: Rectangle {
                id: issue
                required property var modelData
                required property int index

                readonly property string bad: panel.ctl.checkedText.substr(modelData.offset, modelData.length)
                readonly property bool isSpelling: modelData.rule?.issueType === "misspelling"
                readonly property bool active: index === panel.ctl.activeIndex
                readonly property color accent: panel.ctl.issueColor(modelData)

                width: matchList.width - Theme.spacingS
                height: issueColumn.implicitHeight + Theme.spacingS * 2
                radius: Theme.cornerRadius
                // The selected issue takes its underline colour so it stands
                // out from the rest of the list.
                color: active ? Theme.withAlpha(accent, 0.18) : Theme.surfaceContainerHigh
                border.width: active ? 2 : 0
                border.color: accent

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: panel.selectMatch(issue.index)
                }

                Rectangle {
                    width: 3
                    radius: 1.5
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.margins: Theme.spacingS
                    color: issue.accent
                }

                Column {
                    id: issueColumn
                    x: Theme.spacingM + 3
                    y: Theme.spacingS
                    width: parent.width - x - Theme.spacingS
                    spacing: Theme.spacingXS

                    StyledText {
                        width: parent.width
                        elide: Text.ElideRight
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        text: "« " + issue.bad + " » · " + (issue.modelData.rule?.category?.name || "")
                    }

                    StyledText {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceText
                        text: issue.modelData.message
                    }

                    Flow {
                        width: parent.width
                        spacing: Theme.spacingXS

                        Repeater {
                            model: (issue.modelData.replacements || []).slice(0, 6)

                            Rectangle {
                                required property var modelData
                                width: chipLabel.implicitWidth + Theme.spacingM * 2
                                height: chipLabel.implicitHeight + Theme.spacingXS * 2
                                radius: height / 2
                                color: chipArea.containsMouse ? Theme.primary : Theme.primaryContainer

                                StyledText {
                                    id: chipLabel
                                    anchors.centerIn: parent
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: chipArea.containsMouse ? Theme.onPrimary : Theme.onPrimaryContainer
                                    text: parent.modelData.value === "" ? "(supprimer)" : parent.modelData.value
                                }

                                MouseArea {
                                    id: chipArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: panel.applyReplacement(issue.index, parent.modelData.value)
                                }
                            }
                        }

                        Repeater {
                            model: issue.isSpelling ? ["Ignorer", "Ajouter au dictionnaire"] : ["Ignorer"]

                            Rectangle {
                                required property string modelData
                                required property int index
                                width: actionLabel.implicitWidth + Theme.spacingM * 2
                                height: actionLabel.implicitHeight + Theme.spacingXS * 2
                                radius: height / 2
                                color: actionArea.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                                border.width: 1
                                border.color: Theme.outlineVariant

                                StyledText {
                                    id: actionLabel
                                    anchors.centerIn: parent
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    text: parent.modelData
                                }

                                MouseArea {
                                    id: actionArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: parent.index === 0 ? panel.ctl.ignoreMatch(issue.index) : panel.ctl.addToDictionary(issue.index)
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── translation ──
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingS
            visible: panel.ctl.showTranslation && panel.ctl.translationAvailable

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingS

                StyledText {
                    color: Theme.surfaceVariantText
                    text: panel.ctl.sourceLanguage ? panel.ctl.langName(panel.ctl.sourceLanguage) + "  →" : "Langue source inconnue : lancez une vérification"
                }

                DankDropdown {
                    visible: panel.ctl.translationTargets.length > 0
                    dropdownWidth: 160
                    options: panel.ctl.translationTargets.map(c => panel.ctl.langName(c))
                    currentValue: panel.ctl.langName(panel.ctl.effectiveTarget)
                    onValueChanged: value => {
                        const code = panel.ctl.translationTargets.find(c => panel.ctl.langName(c) === value);
                        if (code) {
                            panel.ctl.targetLanguage = code;
                            panel.ctl.saveState("targetLanguage", code);
                            panel.ctl.translation = "";
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                DankButton {
                    text: "Traduire"
                    iconName: "translate"
                    busy: panel.ctl.translating
                    enabled: panel.ctl.effectiveTarget !== "" && panel.ctl.text.trim().length > 0 && !panel.ctl.translating
                    onClicked: panel.ctl.runTranslate()
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: panel.ctl.sourceLanguage !== "" && panel.ctl.translationTargets.length === 0
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                text: "Aucun modèle de traduction installé pour " + panel.ctl.langName(panel.ctl.sourceLanguage) + " (programs.dms-proofreader.translation.models)."
            }

            StyledText {
                Layout.fillWidth: true
                visible: panel.ctl.translationError !== ""
                wrapMode: Text.WordWrap
                color: Theme.error
                text: panel.ctl.translationError
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(panel.height * 0.3, 220)
                visible: panel.ctl.translation !== ""
                radius: Theme.cornerRadius
                color: Theme.surfaceContainerHigh

                Flickable {
                    anchors.fill: parent
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                    }

                    TextArea.flickable: TextArea {
                        readOnly: true
                        selectByMouse: true
                        text: panel.ctl.translation
                        wrapMode: TextArea.Wrap
                        textFormat: TextEdit.PlainText
                        font.family: SettingsData.fontFamily
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceText
                        selectedTextColor: Theme.background
                        selectionColor: Theme.primary
                        padding: Theme.spacingM
                        background: null
                    }
                }
            }

            RowLayout {
                visible: panel.ctl.translation !== ""
                spacing: Theme.spacingS

                DankButton {
                    text: "Copier"
                    iconName: "content_copy"
                    onClicked: panel.ctl.copy(panel.ctl.translation)
                }

                DankButton {
                    text: "Remplacer le texte"
                    iconName: "swap_horiz"
                    onClicked: {
                        panel.replaceAll(panel.ctl.translation);
                        if (panel.ctl.language !== "auto")
                            panel.ctl.language = "auto";
                    }
                }
            }
        }
    }
}

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets

Column {
    id: root

    property alias text: textArea.text
    property alias textArea: textArea
    property bool contentLoaded: false
    property string lastSavedContent: ""
    property var currentTab: NotepadStorageService.tabs.length > NotepadStorageService.currentTabIndex ? NotepadStorageService.tabs[NotepadStorageService.currentTabIndex] : null
    property bool searchVisible: false
    property string searchQuery: ""
    property var searchMatches: []
    property int currentMatchIndex: -1
    property int matchCount: 0

    // Plugin-provided markdown/syntax highlighting (via builtInPluginSettings)
    property bool pluginInstalled: SettingsData.getBuiltInPluginSetting("dankNotepadMarkdown", "enabled", false)
    property bool pluginMarkdownEnabled: SettingsData.getBuiltInPluginSetting("dankNotepadMarkdown", "markdownPreview", false)
    property bool pluginSyntaxEnabled: SettingsData.getBuiltInPluginSetting("dankNotepadMarkdown", "syntaxHighlighting", false)
    property string pluginHighlightedHtml: SettingsData.getBuiltInPluginSetting("dankNotepadMarkdown", "highlightedHtml", "")
    property string pluginFileExtension: SettingsData.getBuiltInPluginSetting("dankNotepadMarkdown", "currentFileExtension", "")

    // Local toggle for markdown preview (can be toggled from UI)
    property bool markdownPreviewActive: pluginMarkdownEnabled

    // Toggle markdown preview
    function toggleMarkdownPreview() {
        if (!markdownPreviewActive) {
            // Entering preview mode
            syncContentToPlugin();
            markdownPreviewActive = true;
        } else {
            // Exiting preview mode
            markdownPreviewActive = false;
        }
    }

    // Local toggle for syntax highlighting preview (read-only view with colors)
    property bool syntaxPreviewActive: false

    // Store original text when entering syntax preview mode
    property string syntaxPreviewOriginalText: ""

    // Function to refresh plugin settings (called from Connections inside TextArea)
    function refreshPluginSettings() {
        pluginInstalled = SettingsData.getBuiltInPluginSetting("dankNotepadMarkdown", "enabled", false);
        pluginMarkdownEnabled = SettingsData.getBuiltInPluginSetting("dankNotepadMarkdown", "markdownPreview", false);
        pluginSyntaxEnabled = SettingsData.getBuiltInPluginSetting("dankNotepadMarkdown", "syntaxHighlighting", false);
        pluginHighlightedHtml = SettingsData.getBuiltInPluginSetting("dankNotepadMarkdown", "highlightedHtml", "");
        pluginFileExtension = SettingsData.getBuiltInPluginSetting("dankNotepadMarkdown", "currentFileExtension", "");

        console.warn("NotepadTextEditor: Plugin settings refreshed. MdEnabled:", pluginMarkdownEnabled, "HtmlLength:", pluginHighlightedHtml.length);
    }

    // Toggle syntax preview mode
    function toggleSyntaxPreview() {
        if (!syntaxPreviewActive) {
            // Entering preview mode
            syncContentToPlugin();
            syntaxPreviewActive = true;
        } else {
            // Exiting preview mode
            syntaxPreviewActive = false;
        }
    }

    // File extension detection for current tab
    readonly property string currentFilePath: currentTab?.filePath || ""
    readonly property string currentFileExtension: {
        if (!currentFilePath)
            return "";
        var parts = currentFilePath.split('.');
        return parts.length > 1 ? parts[parts.length - 1].toLowerCase() : "";
    }

    onCurrentTabChanged: handleCurrentTabChanged()

    Component.onCompleted: handleCurrentTabChanged()

    function handleCurrentTabChanged() {
        if (!currentTab)
            return;

        // Reset preview state ONLY when tab actually changes
        markdownPreviewActive = false;
        syntaxPreviewActive = false;
        syntaxPreviewOriginalText = "";
        textArea.readOnly = false;

        syncContentToPlugin();
    }

    function syncContentToPlugin() {
        if (!currentTab)
            return;

        // Notify plugin of content update
        // console.warn("NotepadTextEditor: Pushing content to plugin. Length:", textArea.text.length, "Path:", currentFilePath);
        SettingsData.setBuiltInPluginSetting("dankNotepadMarkdown", "currentFilePath", currentFilePath);
        SettingsData.setBuiltInPluginSetting("dankNotepadMarkdown", "currentFileExtension", currentFileExtension);
        SettingsData.setBuiltInPluginSetting("dankNotepadMarkdown", "sourceContent", textArea.text);
        SettingsData.setBuiltInPluginSetting("dankNotepadMarkdown", "currentTabChanged", Date.now());
    }

    // Debounce content updates to plugin to keep preview ready
    Timer {
        id: syncTimer
        interval: 500
        repeat: false
        onTriggered: syncContentToPlugin()
    }

    Connections {
        target: textArea
        function onTextChanged() {
            if (!markdownPreviewActive && !syntaxPreviewActive) {
                syncTimer.restart();
            }
        }
    }

    readonly property string fileExtension: {
        if (!currentFilePath)
            return "";
        var parts = currentFilePath.split('.');
        return parts.length > 1 ? parts[parts.length - 1].toLowerCase() : "";
    }
    readonly property bool isMarkdownFile: fileExtension === "md" || fileExtension === "markdown" || fileExtension === "mdown"
    readonly property bool isCodeFile: fileExtension !== "" && fileExtension !== "txt" && !isMarkdownFile

    signal saveRequested
    signal openRequested
    signal newRequested
    signal escapePressed
    signal contentChanged
    signal settingsRequested

    function hasUnsavedChanges() {
        if (!currentTab || !contentLoaded) {
            return false;
        }

        if (currentTab.isTemporary) {
            return textArea.text.length > 0;
        }

        // If in preview mode, compare original text
        if (markdownPreviewActive || syntaxPreviewActive) {
            return syntaxPreviewOriginalText !== lastSavedContent;
        }

        return textArea.text !== lastSavedContent;
    }

    function loadCurrentTabContent() {
        if (!currentTab)
            return;
        contentLoaded = false;
        // Reset preview states on load
        markdownPreviewActive = false;
        syntaxPreviewActive = false;
        syntaxPreviewOriginalText = "";

        NotepadStorageService.loadTabContent(NotepadStorageService.currentTabIndex, content => {
            lastSavedContent = content;
            textArea.text = content;
            contentLoaded = true;
            textArea.readOnly = false;
        });
    }

    function saveCurrentTabContent() {
        if (!currentTab || !contentLoaded)
            return;

        // If in preview mode, save the original text, NOT the HTML
        var contentToSave = (markdownPreviewActive || syntaxPreviewActive) ? syntaxPreviewOriginalText : textArea.text;

        NotepadStorageService.saveTabContent(NotepadStorageService.currentTabIndex, contentToSave);
        lastSavedContent = contentToSave;
    }

    function autoSaveToSession() {
        if (!currentTab || !contentLoaded)
            return;
        saveCurrentTabContent();
    }

    function setTextDocumentLineHeight() {
        return;
    }

    property string lastTextForLineModel: ""
    property var lineModel: []

    function updateLineModel() {
        if (!SettingsData.notepadShowLineNumbers) {
            lineModel = [];
            lastTextForLineModel = "";
            return;
        }

        // In preview mode, line numbers might not match visual lines correctly due to wrapping/HTML
        // But for now let's use the current text (plain or HTML)
        if (textArea.text !== lastTextForLineModel || lineModel.length === 0) {
            lastTextForLineModel = textArea.text;
            lineModel = textArea.text.split('\n');
        }
    }

    function performSearch() {
        let matches = [];
        currentMatchIndex = -1;

        if (!searchQuery || searchQuery.length === 0) {
            searchMatches = [];
            matchCount = 0;
            textArea.select(0, 0);
            return;
        }

        const text = textArea.text;
        const query = searchQuery.toLowerCase();
        let index = 0;

        while (index < text.length) {
            const foundIndex = text.toLowerCase().indexOf(query, index);
            if (foundIndex === -1)
                break;
            matches.push({
                start: foundIndex,
                end: foundIndex + searchQuery.length
            });
            index = foundIndex + 1;
        }

        searchMatches = matches;
        matchCount = matches.length;

        if (matchCount > 0) {
            currentMatchIndex = 0;
            highlightCurrentMatch();
        } else {
            textArea.select(0, 0);
        }
    }

    function highlightCurrentMatch() {
        if (currentMatchIndex >= 0 && currentMatchIndex < searchMatches.length) {
            const match = searchMatches[currentMatchIndex];

            textArea.cursorPosition = match.start;
            textArea.moveCursorSelection(match.end, TextEdit.SelectCharacters);

            const flickable = textArea.parent;
            if (flickable && flickable.contentY !== undefined) {
                const lineHeight = textArea.font.pixelSize * 1.5;
                const approxLine = textArea.text.substring(0, match.start).split('\n').length;
                const targetY = approxLine * lineHeight - flickable.height / 2;
                flickable.contentY = Math.max(0, Math.min(targetY, flickable.contentHeight - flickable.height));
            }
        }
    }

    function findNext() {
        if (matchCount === 0 || searchMatches.length === 0)
            return;
        currentMatchIndex = (currentMatchIndex + 1) % matchCount;
        highlightCurrentMatch();
    }

    function findPrevious() {
        if (matchCount === 0 || searchMatches.length === 0)
            return;
        currentMatchIndex = currentMatchIndex <= 0 ? matchCount - 1 : currentMatchIndex - 1;
        highlightCurrentMatch();
    }

    function showSearch() {
        searchVisible = true;
        Qt.callLater(() => {
            searchField.forceActiveFocus();
        });
    }

    function hideSearch() {
        searchVisible = false;
        searchQuery = "";
        searchMatches = [];
        matchCount = 0;
        currentMatchIndex = -1;
        textArea.select(0, 0);
        textArea.forceActiveFocus();
    }

    spacing: Theme.spacingM

    StyledRect {
        id: searchBar
        width: parent.width
        height: 48
        visible: searchVisible
        opacity: searchVisible ? 1 : 0
        color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
        border.color: searchField.activeFocus ? Theme.primary : Theme.outlineMedium
        border.width: searchField.activeFocus ? 2 : 1
        radius: Theme.cornerRadius

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.shortDuration
                easing.type: Theme.standardEasing
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.spacingM
            anchors.rightMargin: Theme.spacingM
            spacing: Theme.spacingS

            // Search icon
            DankIcon {
                Layout.alignment: Qt.AlignVCenter
                name: "search"
                size: Theme.iconSize - 2
                color: searchField.activeFocus ? Theme.primary : Theme.surfaceVariantText
            }

            // Search input field
            TextInput {
                id: searchField
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                height: 32
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceText
                verticalAlignment: TextInput.AlignVCenter
                selectByMouse: true
                clip: true

                Component.onCompleted: {
                    text = root.searchQuery;
                }

                Connections {
                    target: root
                    function onSearchQueryChanged() {
                        if (searchField.text !== root.searchQuery) {
                            searchField.text = root.searchQuery;
                        }
                    }
                }

                onTextChanged: {
                    if (root.searchQuery !== text) {
                        root.searchQuery = text;
                        root.performSearch();
                    }
                }
                Keys.onEscapePressed: event => {
                    root.hideSearch();
                    event.accepted = true;
                }
                Keys.onReturnPressed: event => {
                    if (event.modifiers & Qt.ShiftModifier) {
                        root.findPrevious();
                    } else {
                        root.findNext();
                    }
                    event.accepted = true;
                }
                Keys.onEnterPressed: event => {
                    if (event.modifiers & Qt.ShiftModifier) {
                        root.findPrevious();
                    } else {
                        root.findNext();
                    }
                    event.accepted = true;
                }
            }

            // Placeholder text
            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: I18n.tr("Find in note...")
                font: searchField.font
                color: Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, 0.5)
                visible: searchField.text.length === 0 && !searchField.activeFocus
                Layout.leftMargin: -(searchField.width - 20) // Position over the input field
            }

            // Match count display
            StyledText {
                Layout.alignment: Qt.AlignVCenter
                text: matchCount > 0 ? "%1/%2".arg(currentMatchIndex + 1).arg(matchCount) : searchQuery.length > 0 ? I18n.tr("No matches") : ""
                font.pixelSize: Theme.fontSizeSmall
                color: matchCount > 0 ? Theme.primary : Theme.surfaceTextMedium
                visible: searchQuery.length > 0
                Layout.rightMargin: Theme.spacingS
            }

            // Navigation buttons
            DankActionButton {
                id: prevButton
                Layout.alignment: Qt.AlignVCenter
                iconName: "keyboard_arrow_up"
                iconSize: Theme.iconSize
                iconColor: matchCount > 0 ? Theme.surfaceText : Theme.surfaceTextAlpha
                enabled: matchCount > 0
                onClicked: root.findPrevious()
            }

            DankActionButton {
                id: nextButton
                Layout.alignment: Qt.AlignVCenter
                iconName: "keyboard_arrow_down"
                iconSize: Theme.iconSize
                iconColor: matchCount > 0 ? Theme.surfaceText : Theme.surfaceTextAlpha
                enabled: matchCount > 0
                onClicked: root.findNext()
            }

            // Close button
            DankActionButton {
                id: closeSearchButton
                Layout.alignment: Qt.AlignVCenter
                iconName: "close"
                iconSize: Theme.iconSize - 2
                iconColor: Theme.surfaceText
                onClicked: root.hideSearch()
            }
        }
    }

    StyledRect {
        width: parent.width
        height: parent.height - bottomControls.height - Theme.spacingM - (searchVisible ? searchBar.height + Theme.spacingM : 0)
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, Theme.notepadTransparency)
        border.color: Theme.outlineMedium
        border.width: 1
        radius: Theme.cornerRadius

        DankFlickable {
            id: flickable
            visible: !root.markdownPreviewActive && !root.syntaxPreviewActive
            anchors.fill: parent
            anchors.margins: 1
            clip: true
            contentWidth: width - 11

            Rectangle {
                id: lineNumberArea
                anchors.left: parent.left
                anchors.top: parent.top
                width: SettingsData.notepadShowLineNumbers ? Math.max(30, 32 + Theme.spacingXS) : 0
                height: textArea.contentHeight + textArea.topPadding + textArea.bottomPadding
                color: "transparent"
                visible: SettingsData.notepadShowLineNumbers

                ListView {
                    id: lineNumberList
                    anchors.top: parent.top
                    anchors.topMargin: textArea.topPadding
                    anchors.right: parent.right
                    anchors.rightMargin: 2
                    width: 32
                    height: textArea.contentHeight
                    model: SettingsData.notepadShowLineNumbers ? root.lineModel : []
                    interactive: false
                    spacing: 0

                    delegate: Item {
                        id: lineDelegate
                        required property int index
                        required property string modelData
                        width: 32
                        height: measuringText.contentHeight

                        Text {
                            id: measuringText
                            width: textArea.width - textArea.leftPadding - textArea.rightPadding
                            text: modelData || " "
                            font: textArea.font
                            wrapMode: Text.Wrap
                            visible: false
                        }

                        StyledText {
                            anchors.right: parent.right
                            anchors.rightMargin: 4
                            anchors.top: parent.top
                            text: index + 1
                            font.family: textArea.font.family
                            font.pixelSize: textArea.font.pixelSize
                            color: Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, 0.4)
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }
            }

            TextArea.flickable: TextArea {
                id: textArea
                placeholderText: ""
                placeholderTextColor: Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, 0.5)
                font.family: SettingsData.notepadUseMonospace ? SettingsData.monoFontFamily : (SettingsData.notepadFontFamily || SettingsData.fontFamily)
                font.pixelSize: SettingsData.notepadFontSize * SettingsData.fontScale
                font.letterSpacing: 0
                color: Theme.surfaceText
                selectedTextColor: Theme.background
                selectionColor: Theme.primary
                selectByMouse: true
                selectByKeyboard: true
                wrapMode: TextArea.Wrap
                focus: true
                activeFocusOnTab: true
                textFormat: TextEdit.PlainText
                // readOnly: root.syntaxPreviewActive || root.markdownPreviewActive // Handled by visibility now
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                persistentSelection: true
                tabStopDistance: 40
                leftPadding: (SettingsData.notepadShowLineNumbers ? lineNumberArea.width + Theme.spacingXS : Theme.spacingM)
                topPadding: Theme.spacingM
                rightPadding: Theme.spacingM
                bottomPadding: Theme.spacingM
                cursorDelegate: Rectangle {
                    width: 1.5
                    radius: 1
                    color: Theme.surfaceText
                    x: textArea.cursorRectangle.x
                    y: textArea.cursorRectangle.y
                    height: textArea.cursorRectangle.height
                    opacity: 1.0

                    SequentialAnimation on opacity {
                        running: textArea.activeFocus
                        loops: Animation.Infinite
                        PropertyAnimation {
                            from: 1.0
                            to: 0.0
                            duration: 650
                            easing.type: Easing.InOutQuad
                        }
                        PropertyAnimation {
                            from: 0.0
                            to: 1.0
                            duration: 650
                            easing.type: Easing.InOutQuad
                        }
                    }
                }

                Component.onCompleted: {
                    loadCurrentTabContent();
                    setTextDocumentLineHeight();
                    root.updateLineModel();
                    Qt.callLater(() => {
                        textArea.forceActiveFocus();
                    });
                }

                Connections {
                    target: NotepadStorageService
                    function onCurrentTabIndexChanged() {
                        // Exit syntax preview mode when switching tabs
                        if (root.syntaxPreviewActive) {
                            root.syntaxPreviewActive = false;
                        }
                        loadCurrentTabContent();
                        Qt.callLater(() => {
                            textArea.forceActiveFocus();
                        });
                    }
                    function onTabsChanged() {
                        if (NotepadStorageService.tabs.length > 0 && !contentLoaded) {
                            loadCurrentTabContent();
                        }
                    }
                }

                Connections {
                    target: SettingsData
                    function onNotepadShowLineNumbersChanged() {
                        root.updateLineModel();
                    }
                    function onBuiltInPluginSettingsChanged() {
                        root.refreshPluginSettings();
                    }
                }

                onTextChanged: {
                    if (contentLoaded && text !== lastSavedContent) {
                        autoSaveTimer.restart();
                    }
                    root.contentChanged();
                    root.updateLineModel();
                }

                Keys.onEscapePressed: event => {
                    root.escapePressed();
                    event.accepted = true;
                }

                Keys.onPressed: event => {
                    if (event.modifiers & Qt.ControlModifier) {
                        switch (event.key) {
                        case Qt.Key_S:
                            event.accepted = true;
                            root.saveRequested();
                            break;
                        case Qt.Key_O:
                            event.accepted = true;
                            root.openRequested();
                            break;
                        case Qt.Key_N:
                            event.accepted = true;
                            root.newRequested();
                            break;
                        case Qt.Key_A:
                            event.accepted = true;
                            selectAll();
                            break;
                        case Qt.Key_F:
                            event.accepted = true;
                            root.showSearch();
                            break;
                        }
                    }
                }

                background: Rectangle {
                    color: "transparent"
                }

                // Make links clickable in markdown preview mode
                onLinkActivated: link => {
                    Qt.openUrlExternally(link);
                }
            }

            StyledText {
                id: placeholderOverlay
                text: I18n.tr("Start typing your notes here...")
                color: Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, 0.5)
                font.family: textArea.font.family
                font.pixelSize: textArea.font.pixelSize
                visible: textArea.text.length === 0
                anchors.left: textArea.left
                anchors.top: textArea.top
                anchors.leftMargin: textArea.leftPadding
                anchors.topMargin: textArea.topPadding
                z: textArea.z + 1
            }
        }

        // Dedicated Flickable for Preview Mode
        DankFlickable {
            id: previewFlickable
            visible: root.markdownPreviewActive || root.syntaxPreviewActive
            anchors.fill: parent
            anchors.margins: 1
            clip: true
            contentWidth: width - 11

            TextArea.flickable: TextArea {
                id: previewAreaReal
                text: root.pluginHighlightedHtml
                textFormat: TextEdit.RichText
                readOnly: true

                // Copy styling from main textArea
                placeholderText: ""
                font.family: SettingsData.notepadUseMonospace ? SettingsData.monoFontFamily : (SettingsData.notepadFontFamily || SettingsData.fontFamily)
                font.pixelSize: SettingsData.notepadFontSize * SettingsData.fontScale
                font.letterSpacing: 0
                color: Theme.surfaceText
                selectedTextColor: Theme.background
                selectionColor: Theme.primary
                selectByMouse: true
                selectByKeyboard: true
                wrapMode: TextArea.Wrap
                focus: true
                activeFocusOnTab: true

                leftPadding: Theme.spacingM
                topPadding: Theme.spacingM
                rightPadding: Theme.spacingM
                bottomPadding: Theme.spacingM

                // Make links clickable
                onLinkActivated: link => {
                    Qt.openUrlExternally(link);
                }
            }
        }
    }

    Column {
        id: bottomControls
        width: parent.width
        spacing: Theme.spacingS

        Item {
            width: parent.width
            height: 32

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingL

                Row {
                    spacing: Theme.spacingS
                    DankActionButton {
                        iconName: "save"
                        iconSize: Theme.iconSize - 2
                        iconColor: Theme.primary
                        enabled: currentTab && (hasUnsavedChanges() || textArea.text.length > 0)
                        onClicked: root.saveRequested()
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("Save")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceTextMedium
                    }
                }

                Row {
                    spacing: Theme.spacingS
                    DankActionButton {
                        iconName: "folder_open"
                        iconSize: Theme.iconSize - 2
                        iconColor: Theme.secondary
                        onClicked: root.openRequested()
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("Open")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceTextMedium
                    }
                }

                Row {
                    spacing: Theme.spacingS
                    DankActionButton {
                        iconName: "note_add"
                        iconSize: Theme.iconSize - 2
                        iconColor: Theme.surfaceText
                        onClicked: root.newRequested()
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("New")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceTextMedium
                    }
                }

                // Markdown preview toggle (only visible when plugin installed and viewing .md file)
                Row {
                    spacing: Theme.spacingS
                    visible: root.pluginInstalled && root.isMarkdownFile

                    DankActionButton {
                        iconName: root.markdownPreviewActive ? "visibility" : "visibility_off"
                        iconSize: Theme.iconSize - 2
                        iconColor: root.markdownPreviewActive ? Theme.primary : Theme.surfaceTextMedium
                        onClicked: root.toggleMarkdownPreview()
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("Preview")
                        font.pixelSize: Theme.fontSizeSmall
                        color: root.markdownPreviewActive ? Theme.primary : Theme.surfaceTextMedium
                    }
                }

                // Syntax highlighting toggle (only visible when plugin installed and viewing code file)
                Row {
                    spacing: Theme.spacingS
                    visible: root.pluginInstalled && root.pluginSyntaxEnabled && root.isCodeFile

                    DankActionButton {
                        iconName: root.syntaxPreviewActive ? "code" : "code_off"
                        iconSize: Theme.iconSize - 2
                        iconColor: root.syntaxPreviewActive ? Theme.primary : Theme.surfaceTextMedium
                        onClicked: root.toggleSyntaxPreview()
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.syntaxPreviewActive ? I18n.tr("Edit") : I18n.tr("Highlight")
                        font.pixelSize: Theme.fontSizeSmall
                        color: root.syntaxPreviewActive ? Theme.primary : Theme.surfaceTextMedium
                    }
                }
            }

            DankActionButton {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconName: "more_horiz"
                iconSize: Theme.iconSize - 2
                iconColor: Theme.surfaceText
                onClicked: root.settingsRequested()
            }
        }

        Row {
            width: parent.width
            spacing: Theme.spacingL

            StyledText {
                text: textArea.text.length > 0 ? I18n.tr("%1 characters").arg(textArea.text.length) : I18n.tr("Empty")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceTextMedium
            }

            StyledText {
                text: I18n.tr("Lines: %1").arg(textArea.lineCount)
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceTextMedium
                visible: textArea.text.length > 0
                opacity: 1.0
            }

            StyledText {
                text: {
                    if (autoSaveTimer.running) {
                        return I18n.tr("Auto-saving...");
                    }

                    if (hasUnsavedChanges()) {
                        if (currentTab && currentTab.isTemporary) {
                            return I18n.tr("Unsaved note...");
                        } else {
                            return I18n.tr("Unsaved changes");
                        }
                    } else {
                        return I18n.tr("Saved");
                    }
                }
                font.pixelSize: Theme.fontSizeSmall
                color: {
                    if (autoSaveTimer.running) {
                        return Theme.primary;
                    }

                    if (hasUnsavedChanges()) {
                        return Theme.warning;
                    } else {
                        return Theme.success;
                    }
                }
                opacity: textArea.text.length > 0 ? 1.0 : 0.0
            }
        }
    }

    Timer {
        id: autoSaveTimer
        interval: 2000
        repeat: false
        onTriggered: {
            autoSaveToSession();
        }
    }
}

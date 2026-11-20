import QtQuick
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets as DCommon

// The proofreader as a regular window, framed like the DMS Notepad's popout.
DFloatingWindow {
    id: win

    required property var ctl

    function show() {
        visible = true;
    }

    function hide() {
        visible = false;
    }

    function toggle() {
        visible = !visible;
    }

    title: "Correcteur"
    minimumSize: Qt.size(360, 320)
    implicitWidth: 640
    implicitHeight: 760
    surfaceColor: Theme.notepadWindowSurface
    visible: false

    onVisibleChanged: {
        if (visible)
            Qt.callLater(panel.onShown);
    }

    onClosed: win.visible = false

    Item {
        anchors.fill: parent

        DCommon.DWindowHeader {
            id: titleBar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            z: 10
            controls: windowControls
            title: "Correcteur"
            onCloseRequested: win.hide()
        }

        ProofreaderPanel {
            id: panel
            anchors.top: titleBar.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Theme.windowInset
            anchors.topMargin: 0
            // Not `ctl: ctl` / `host: host`: inside the panel those names are
            // its own, still unset, properties.
            ctl: win.ctl
            host: win
            inPopout: true
        }
    }

    FloatingWindowControls {
        id: windowControls
        targetWindow: win
    }
}

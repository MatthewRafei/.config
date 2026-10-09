import QtQuick
import qs
import qs.widgets

// Settings > Keyboard: the typing test (TypingTest.qml).
Column {
    property var service
    spacing: 14

    Section { text: "TYPING TEST" }
    TypingTest { width: parent.width }
}

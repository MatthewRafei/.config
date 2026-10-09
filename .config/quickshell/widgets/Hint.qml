import QtQuick
import qs

// Small explanatory text under a setting; wraps to the parent's width.
Text {
    width: parent ? parent.width : 0
    wrapMode: Text.Wrap
    color: Theme.textFaint
    font.family: Theme.fontFamily
    font.pixelSize: 10
}

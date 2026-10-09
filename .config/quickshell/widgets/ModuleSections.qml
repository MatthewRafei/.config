import QtQuick
import qs

// Blocks that active modules add to a core Settings page (module.json
// "sections"). Put one where they should appear: ModuleSections { page: "Network" }
Column {
    id: host
    property string page
    width: parent ? parent.width : 0
    spacing: 14

    Repeater {
        model: Modules.sections(host.page)
        Loader {
            id: sec
            required property var modelData
            width: host.width
            Component.onCompleted: setSource(modelData.url, { service: Modules.service(modelData.id) })
        }
    }
}

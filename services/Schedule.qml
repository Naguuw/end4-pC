pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Schedule manager singleton for weekly college/school timetable.
 * Days are 0 (Monday) to 6 (Sunday).
 */
Singleton {
    id: root
    property var filePath: Directories.schedulePath
    property var list: []

    function addItem(day, title, startTime, endTime, room, lecturer, note) {
        const item = {
            "id": Date.now().toString() + "-" + Math.floor(Math.random() * 10000),
            "day": Number(day ?? 0),
            "title": (title ?? "").trim(),
            "startTime": (startTime ?? "").trim(),
            "endTime": (endTime ?? "").trim(),
            "room": (room ?? "").trim(),
            "lecturer": (lecturer ?? "").trim(),
            "note": (note ?? "").trim()
        }
        list.push(item)
        root.list = list.slice(0)
        scheduleFileView.setText(JSON.stringify(root.list, null, 2))
        return item.id
    }

    function updateItem(id, day, title, startTime, endTime, room, lecturer, note) {
        const idx = list.findIndex(item => item.id === id)
        if (idx >= 0) {
            list[idx] = {
                "id": id,
                "day": Number(day ?? list[idx].day),
                "title": (title ?? list[idx].title).trim(),
                "startTime": (startTime ?? list[idx].startTime).trim(),
                "endTime": (endTime ?? list[idx].endTime).trim(),
                "room": (room ?? list[idx].room).trim(),
                "lecturer": (lecturer ?? list[idx].lecturer).trim(),
                "note": (note ?? list[idx].note).trim()
            }
            root.list = list.slice(0)
            scheduleFileView.setText(JSON.stringify(root.list, null, 2))
        }
    }

    function deleteItem(id) {
        const idx = list.findIndex(item => item.id === id)
        if (idx >= 0) {
            list.splice(idx, 1)
            root.list = list.slice(0)
            scheduleFileView.setText(JSON.stringify(root.list, null, 2))
        }
    }

    function getScheduleForDay(day) {
        const targetDay = Number(day)
        return (root.list || [])
            .filter(item => Number(item.day) === targetDay)
            .sort((a, b) => {
                const timeA = (a.startTime || "00:00")
                const timeB = (b.startTime || "00:00")
                return timeA.localeCompare(timeB)
            })
    }

    function hasScheduleOnDay(day) {
        const targetDay = Number(day)
        return (root.list || []).some(item => Number(item.day) === targetDay)
    }

    function refresh() {
        scheduleFileView.reload()
    }

    Component.onCompleted: {
        refresh()
    }

    FileView {
        id: scheduleFileView
        path: Qt.resolvedUrl(root.filePath)
        onLoaded: {
            const fileContents = scheduleFileView.text()
            try {
                const parsed = JSON.parse(fileContents)
                root.list = Array.isArray(parsed) ? parsed : []
            } catch (e) {
                console.log("[Schedule] Corrupt or empty file, resetting to empty list. Error: " + e)
                root.list = []
                scheduleFileView.setText(JSON.stringify(root.list, null, 2))
            }
            console.log("[Schedule] File loaded")
        }
        onLoadFailed: (error) => {
            if (error == FileViewError.FileNotFound) {
                console.log("[Schedule] File not found, creating new file.")
                root.list = []
                scheduleFileView.setText(JSON.stringify(root.list, null, 2))
            } else {
                console.log("[Schedule] Error loading file: " + error)
            }
        }
    }
}

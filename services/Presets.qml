pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    property alias folderModel: presetsFolderModel
    property alias onlineFolderModel: onlinePresetsFolderModel
    property alias importedFolderModel: importedPresetsFolderModel

    FolderListModel {
        id: presetsFolderModel
        folder: Qt.resolvedUrl(Directories.userPresetsPath)
        showDirs: false
        nameFilters: ["*.json"]
    }

    FolderListModel {
        id: onlinePresetsFolderModel
        folder: Qt.resolvedUrl(`${Quickshell.env("HOME")}/.cache/quickshell/presets`)
        showDirs: false
        nameFilters: ["*.json"]
    }

    FolderListModel {
        id: importedPresetsFolderModel
        folder: Qt.resolvedUrl(`${Quickshell.env("HOME")}/.cache/quickshell/presets_imported`)
        showDirs: false
        nameFilters: ["*.json"]
    }

    function refresh() {
        const current = presetsFolderModel.folder;
        presetsFolderModel.folder = "";
        presetsFolderModel.folder = current;
    }

    function refreshOnline() {
        const current = onlinePresetsFolderModel.folder;
        onlinePresetsFolderModel.folder = "";
        onlinePresetsFolderModel.folder = current;
    }

    function refreshImported() {
        const current = importedPresetsFolderModel.folder;
        importedPresetsFolderModel.folder = "";
        importedPresetsFolderModel.folder = current;
    }

    function sanitizeName(rawName) {
        let name = (rawName ?? "").trim()
            .replace(/\s+/g, "_")
            .replace(/[\/\u0000-\u001f]/g, "");
        name = name.replace(/^\.+/, "");
        return name;
    }

    function splitNameDescription(rawInput) {
        const raw = (rawInput ?? "").trim();
        const commaIndex = raw.indexOf(",");
        if (commaIndex === -1)
            return { name: raw, description: undefined };
        return {
            name: raw.substring(0, commaIndex).trim(),
            description: raw.substring(commaIndex + 1).trim()
        };
    }

    function presetExists(name) {
        for (let i = 0; i < presetsFolderModel.count; i++) {
            if (presetNameAt(i) === name) return true;
        }
        return false;
    }

    function presetNameAt(index) {
        const fileName = presetsFolderModel.get(index, "fileName") ?? "";
        return fileName.replace(/\.json$/, "");
    }

    function notify(message, isError = false) {
        const args = ["notify-send", "-a", "Shell", Translation.tr("Presets"), message];
        if (isError) args.push("-u", "critical");
        Quickshell.execDetached(args);
    }

    function runJob(job) {
        if (scriptProc.job !== null) {
            scriptProc.pendingJob = job;
            return;
        }
        scriptProc.job = job;
        scriptProc.command = ["bash", Directories.presetsScriptPath].concat(job.args);
        scriptProc.running = true;
    }

    Process {
        id: scriptProc
        property var job: null
        property var pendingJob: null

        onExited: (exitCode, exitStatus) => {
            const finished = scriptProc.job;
            scriptProc.job = null;
            if (finished !== null) {
                root.refresh();
            }
            const next = scriptProc.pendingJob;
            scriptProc.pendingJob = null;
            if (next !== null) root.runJob(next);
        }
    }

    Process {
        id: applyProc
        onExited: (exitCode, exitStatus) => {
            Config.reloadFile();
            Config.blockWrites = false;
        }
    }

    Process {
        id: deleteOnlineProc
        onExited: root.refreshOnline()
    }

    Process {
        id: deleteImportedProc
        onExited: root.refreshImported()
    }

    Process {
        id: overwriteProc
        onExited: root.refresh()
    }

    Process {
        id: exportZipProc
    }

    Process {
        id: importZipProc
        onExited: root.refreshImported()
    }

    function save(rawInput) {
        const { name, description } = splitNameDescription(rawInput);
        const clean = sanitizeName(name);
        if (clean.length === 0) return;
        Config.flush();
        runJob({
            args: ["--save", clean].concat(description !== undefined ? [description] : []),
        });
    }

    function apply(name, wallpaperPath) {
        const clean = sanitizeName(name);
        if (clean.length === 0 || applyProc.running) return;
        GlobalStates.settingsOpen = false;
        Wallpapers.confirmedPath = wallpaperPath ?? "";
        Wallpapers.previewPath = "";
        Config.flush();
        Config.blockWrites = true;
        applyProc.command = ["bash", Directories.presetsScriptPath, "--apply", clean];
        applyProc.running = true;
    }

    function applyOnline(name) {
        GlobalStates.settingsOpen = false;
        Wallpapers.confirmedPath = "";
        Wallpapers.previewPath = "";
        Quickshell.execDetached(["bash", Directories.presetsScriptPath, "--apply", name, "--online"]);
    }

    function applyImported(name, wallpaperPath) {
        GlobalStates.settingsOpen = false;
        Wallpapers.confirmedPath = wallpaperPath ?? "";
        Wallpapers.previewPath = "";
        Quickshell.execDetached(["bash", Directories.presetsScriptPath, "--apply", name, "--imported"]);
    }

    function remove(name) {
        const clean = sanitizeName(name);
        if (clean.length === 0) return;
        runJob({
            args: ["--remove", clean],
        });
    }

    function removeOnline(name) {
        deleteOnlineProc.command = ["bash", Directories.presetsScriptPath, "--remove", name, "--online"];
        deleteOnlineProc.running = true;
    }

    function removeImported(name) {
        deleteImportedProc.command = ["bash", Directories.presetsScriptPath, "--remove", name, "--imported"];
        deleteImportedProc.running = true;
    }

    function rename(oldName, rawInput) {
        const old = sanitizeName(oldName);
        if (old.length === 0) return;
        const { name, description } = splitNameDescription(rawInput);
        const clean = sanitizeName(name);
        if (clean.length === 0) {
            notify(Translation.tr("Invalid preset name"), true);
            return;
        }
        if (clean !== old && presetExists(clean)) {
            notify(Translation.tr("A preset named %1 already exists").arg(clean), true);
            return;
        }
        const args = ["--rename", old, clean];
        if (description !== undefined) args.push(description);
        runJob({
            args: args,
        });
    }

    function overwrite(name) {
        Config.flush();
        overwriteProc.command = ["bash", Directories.presetsScriptPath, "--save", name];
        overwriteProc.running = true;
    }

    function exportZip(name) {
        exportZipProc.command = ["bash", Directories.presetsScriptPath, "--export-zip", name];
        exportZipProc.running = true;
    }

    function importZip(path) {
        const clean = String(path).replace(/^file:\/\//, "");
        importZipProc.command = ["bash", Directories.presetsScriptPath, "--import-zip", clean];
        importZipProc.running = true;
    }
}

#!/usr/bin/env bash
# SUDO_ASKPASS helper: prompts for the sudo password in a GUI dialog.
# The password is printed to stdout where sudo consumes it directly,
# so it never appears in the chat transcript, logs, or process arguments.

PROMPT="${1:-Password}"
DIALOG_TITLE="AI Assistant: Sudo Password"

dialog_kdialog() {
	kdialog --title "$DIALOG_TITLE" --password "$PROMPT"
}

dialog_zenity() {
	zenity --password --title "$DIALOG_TITLE" 2> /dev/null
}

for dialog_name in kdialog zenity; do
	if ! command -v "$dialog_name" > /dev/null 2>&1; then
		continue
	fi
	password=$("dialog_$dialog_name")
	status=$?
	if [[ $status -ne 0 ]]; then
		# The dialog tool exists but was cancelled — do not nag with another one
		break
	fi
	if [[ -n "$password" ]]; then
		printf '%s' "$password"
		exit 0
	fi
done

notify-send "Sudo cancelled" "The password dialog was dismissed or no dialog tool is available." -a "Shell" 2> /dev/null
exit 1

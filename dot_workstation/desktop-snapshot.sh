#!/usr/bin/bash
set -xeuo pipefail

main() {
	WORKSTATION="$HOME/.workstation"
	LEADER="$WORKSTATION/restic-leader"
	MID=$(cat "/etc/machine-id")

	# Only allow snapshot from leader...
	# TODO create desktop-leader.sh which allows machine to set self as leader
	# this would solve the issue of migrating to a new machine for primary use.
	if [ "$MID" != "$(head -1 "$LEADER")" ]; then
		echo "Not leader; gracefully exiting..."
		exit 0
	fi

	# Update dconf database
	DCONF="$WORKSTATION/dconf.ini"
	rm -f "$DCONF"
	dconf dump / >"$DCONF"

	# Backup to Backblaze
	cd ~

	# Init credentials
	source "$WORKSTATION/restic-env"

	# Backup all files matching restic-includes.txt
	restic backup --verbose --files-from="$WORKSTATION/restic-includes.txt" --exclude-file="$WORKSTATION/restic-excludes.txt"

	# Prune backups according to policy:
	#
	# @see https://restic.readthedocs.io/en/stable/060_forget.html#removing-snapshots-according-to-a-policy
	#
	# - Keep the last 7 daily snapshots.
	# - Keep 5 total snapshots for each of the last 5 weeks.
	# - Keep 12 total snapshots for each of thel last 12 months.
	# - Keep 60 total snapshots for each of the last 40 years.
	restic forget --prune --keep-daily 7 --keep-weekly 5 --keep-monthly 12 --keep-yearly 40

	# Display restic stats
	restic snapshots
	restic stats

	# Store latest short_id in restic-latest
	LATEST=$(restic snapshots --json | jq .[-1].short_id -r)
	TRACKER="$WORKSTATION/restic-latest"
	rm -f "$TRACKER"
	echo "$LATEST" >>"$TRACKER"
	chezmoi add "$TRACKER"

	# Recreate leader file to
	# track which machine did snapshot
	HOST=$(fastfetch | grep "Host: ")
	OS=$(fastfetch | grep "OS: ")
	rm -f "$LEADER"
	{
		echo "$MID"
		echo "$HOST"
		echo "$OS"
	} >>"$LEADER"
	chezmoi add "$LEADER"
}

main "${@}"

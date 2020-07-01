#!/usr/bin/env bash

# SOURCE:
# https://github.com/jamf/MakeMeAnAdmin

###############################################
# This script will provide temporary admin    #
# rights to a standard user right from self   #
# service. First it will grab the username of #
# the logged in user, elevate them to admin   #
# and then create a launch daemon that will   #
# count down from 30 minutes and then create  #
# and run a secondary script that will demote #
# the user back to a standard account. The    #
# launch daemon will continue to count down   #
# no matter how often the user logs out or    #
# restarts their computer.                    #
###############################################

# activate verbose standard output (stdout)
set -v
# activate debugging (execution shown)
set -x

# logs (DEBUGGING ONLY -- disable as it stores params creds on host machine)
# log_time=$(date +%Y%m%d_%H%M%S)
# log_file="/tmp/$(basename "$0" | cut -d. -f1)_$log_time.log" # LOCAL only
# log_file="/tmp/make_admin_$log_time.log"
# exec &> >(tee -a "$log_file")   # redirect standard error (stderr) and stdout to log
# exec 1>> >(tee -a "$log_file")	# redirect stdout to log

# Working directory
# script_dir=$(cd "$(dirname "$0")" && pwd)

# Set $IFS to eliminate whitespace in pathnames
IFS="$(printf '\n\t')"

# Current user
# Param $3 is logged in user in JSS
logged_in_user=$3
# logged_in_user=$(logname) # posix alternative to /dev/console

osascript -e 'display dialog "You will have administrative rights for 30 minutes. Continue? " buttons {"Cancel","Make me an admin, please"} default button 1'
if [[ $? -eq 1 ]]; then
    echo "Ubermensch cancelled "
	set +v
	set +x
	unset IFS
    exit 1
fi

# write a daemon that will let you remove the privilege with another script and chmod/chown to make sure it'll run, then load the daemon
# Create the plist
defaults write /Library/LaunchDaemons/remove_admin.plist Label -string "remove_admin"

# Add program argument to have it run the update script
defaults write /Library/LaunchDaemons/remove_admin.plist ProgramArguments -array -string /bin/bash -string "/Library/Application Support/JAMF/remove_admin_rights.sh"

# Set the run inverval to run every 7 days
defaults write /Library/LaunchDaemons/remove_admin.plist StartInterval -integer 1800

# Set run at load
defaults write /Library/LaunchDaemons/remove_admin.plist RunAtLoad -boolean yes

# Set ownership
chown root:wheel /Library/LaunchDaemons/remove_admin.plist
chmod 644 /Library/LaunchDaemons/remove_admin.plist

# Load the daemon
launchctl load /Library/LaunchDaemons/remove_admin.plist
sleep 10

# Make file for removal
if [[ ! -d '/private/var/user_to_remove' ]]; then
	mkdir -p '/private/var/user_to_remove'
	echo $logged_in_user >> '/private/var/user_to_remove/user'
else
    echo $logged_in_user >> '/private/var/user_to_remove/user'
fi

# Give the user admin privileges
dseditgroup -o edit -a $logged_in_user -t user admin

# heredoc for the launch daemon to run to demote the user back and then pull logs of what the user did.
cat << 'EOF' > /Library/Application\ Support/JAMF/remove_admin_rights.sh
if [[ -f '/private/var/user_to_remove/user' ]]; then
	user_to_remove=$(cat /private/var/user_to_remove/user)
	echo "Removing $user_to_remove's admin privileges"
	dseditgroup -o edit -d $user_to_remove -t user admin
	rm -f '/private/var/user_to_remove/user'
	launchctl unload '/Library/LaunchDaemons/remove_admin.plist'
	rm '/Library/LaunchDaemons/remove_admin.plist'
	log collect --last 30m --output /private/var/user_to_remove/${user_to_remove}_$(date +%Y%m%d_%H%M%S).logarchive
fi
EOF

# Reload System Preferences to remove Profiles pane
if [[ ! -z $(pgrep 'System Preferences') ]]; then
    pkill -1 'System Preferences'
    open '/Applications/System Preferences.app'
fi

# deactivate verbose and debugging stdout
set +v
set +x

unset IFS

exit 0

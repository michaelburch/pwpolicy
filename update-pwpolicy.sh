!/bin/bash
# Configure local password policy 
# libpam-cracklib must be installed first

# Requires root privileges
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run with sudo" 1>&2
   exit 1
fi

# Requirement: Passwords for standard and shared accounts must be reset at least once every year
# This setting is in /etc/login.defs. We replace the line that begins with PASS_MAX_DAYS
# with the required value
MAX_AGE="365"
sed -i "s/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   $MAX_AGE/g" /etc/login.defs
# Apply this setting to all users with a valid login shell
getent passwd | grep -f /etc/shells | sed /nologin/d | sudo cut -f 1 -d: | sudo xargs -n 1 -I {} bash -c " echo {} ; sudo chage -M $MAX_AGE {}"

# Requirement: Passwords may only be changed once per 24 hour period
# This setting is in /etc/login.defs. We replace the line that begins with PASS_MIN_DAYS
# with the required value
MIN_AGE="1"
sed -i "s/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   $MIN_AGE/g" /etc/login.defs
# Apply this setting to all users with a valid login shell
getent passwd | grep -f /etc/shells | sed /nologin/d | sudo cut -f 1 -d: | sudo xargs -n 1 -I {} bash -c " echo {} ; sudo chage -m $MIN_AGE {}"


# Requirement: Passwords for administrative accounts must be reset at least once every 180 days
# At a minimum, this includes the root account
passwd -x 180 root

CFGHEAD="# Custom module config"
if [ -f /etc/pam.d/common-auth  ]; then
 # Add custom module config block to /etc/pam.d/common-password 
 sed -i "/^# here are the per-package modules/i $CFGHEAD" /etc/pam.d/common-auth
fi
# Requirement: Password length and complexity
# Minimum Length - 12
# 3 of the following complexity classes
#  a) at least 1 lowercase letter
#  b) at least 1 uppercase letter
#  c) at least 1 numeric character
#  d) at least one special character 
LENGTH="12"
CLASS="3"

# Requirement: Users will be locked out after 10 failed attempts to enter their password. Accounts will be
# re-enabled after 15 minutes.
# Change retries from 3 to 10
RETRY="10"
DENY="10"
UNLOCK="900"

# Requirement: Users must not re-use any of their 10 previously used passwords
# Remember last 10 passwords. By default these are stored in /etc/security/opasswd
PWHIST="10"
#sed -i 's/\bpam_unix.so\b/& remember=10/' /etc/pam.d/common-password
# Password history will fail if the file doesn't exist and have correct permissions
touch /etc/security/opasswd
chown root:root /etc/security/opasswd
chmod 600 /etc/security/opasswd
# Policy does not specify how many characters must be different. To keep consistent with
# other platforms, change this value to 1
DIFCHAR="1"

# By default, character credits are given for each of the four classes
# so an 8 character password with 1 lower, 1 upper, 1 digit and 1 other 
# would be counted as a 12 character password. This line disables credits 
DISABLE_CRED="lcredit=0 ucredit=0 dcredit=0 ocredit=0"

########
# Debian / Ubuntu based systems use /etc/pam.d/common-password and common-auth
#######
if [ -f /etc/pam.d/common-password ]; then
 # Update pam_unix config
 sudo sed -i "s/\bpam_unix.so\b/& remember=$PWHIST/" /etc/pam.d/common-password

 # Update the pam_cracklib config in /etc/pam.d/common-password 
 sudo sed -i "s/\bpam_cracklib.so\b/& minclass=$CLASS $DISABLE_CRED/" /etc/pam.d/common-password
 sudo sed -i "s/retry=3/retry=$RETRY/" /etc/pam.d/common-password
 sudo sed -i "s/minlen=[[:digit:]]\+/minlen=$LENGTH/" /etc/pam.d/common-password
 sudo sed -i "s/difok=[[:digit:]]\+/difok=$DIFCHAR/" /etc/pam.d/common-password

 # Add a line to common-auth that locks accounts after 10 attempts and unlocks after 15 minutes
 sed  -i "/# Custom module config/a auth    required                        pam_tally2.so deny=$DENY onerr=fail unlock=$UNLOCK" /etc/pam.d/common-auth
fi

########
# Redhat/ CentOS use system-auth, password-auth and pwquality.conf
########
if [ -f /etc/pam.d/system-auth ]; then
 sudo sed -i "/auth        required      pam_env.so/a auth        required      pam_tally2.so deny=$DENY unlock_time=$UNLOCK" /etc/pam.d/system-auth
 sudo sed -i "/account     required      pam_unix.so/a account     required      pam_tally2.so" /etc/pam.d/system-auth
 sudo sed -i "s/^password.*pam_unix.so/& remember=$PWHIST/" /etc/pam.d/system-auth

fi

if [ -f /etc/pam.d/password-auth ]; then

 sudo sed -i "/auth        required      pam_env.so/a auth        required      pam_tally2.so deny=$DENY unlock_time=$UNLOCK" /etc/pam.d/password-auth
 sudo sed -i "/account     required      pam_unix.so/a account     required      pam_tally2.so" /etc/pam.d/password-auth
 sudo sed -i "s/^password.*pam_unix.so/& remember=$PWHIST/" /etc/pam.d/password-auth
fi

if [ -f /etc/security/pwquality.conf ]; then
 # Set difok to 1
 sudo sed -i "s/# difok = [[:digit:]]/difok = $DIFCHAR/" /etc/security/pwquality.conf

 # Set minlen to 12
 sudo sed -i "s/# minlen = [[:digit:]]/minlen = $LENGTH/" /etc/security/pwquality.conf

 # Set minclass to 3
 sudo sed -i "s/# minclass = [[:digit:]]/minclass = $CLASS/" /etc/security/pwquality.conf

 # Set all credit values to 0 and uncomment the lines
 sudo sed -i "/credit = [[:digit:]]/s/[[:digit:]]/0/g" /etc/security/pwquality.conf
 sudo sed -i "/credit = [[:digit:]]/s/^#//g" /etc/security/pwquality.conf

fi

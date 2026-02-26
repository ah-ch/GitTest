#!/bin/bash
# 
# Description: This script sets up developer environment on WSL
# Script Name: setup-devtools.sh
# Author: s1i5fs
# Version: 0.8.0 
# Usage: Run as root, of course.
#
############################################################
# Set script mode
############################################################
set -eu

echo -e "\n---------------------------------------------------"
echo "0. Ensure script is launched with sudo"
echo -e "---------------------------------------------------"
if ! [ "$(id -u)" == "0" ]; then
    echo "We are getting nowhere. Please run this script as root!"
    exit 100
fi


# ----------------------------------------------------------
# Script is launched with sudo where user changes to root.
# However we need the logged-in user
#
# Rationale for using $SUDO_USER
# When a user runs a script with the sudo command the original 
# login name of the user who invoked sudo is stored in 
# the variable $SUDO_USER.
# ----------------------------------------------------------
LOGGED_IN_USER=$SUDO_USER
USER_HOME="$(getent passwd $SUDO_USER | awk -F ':' '{print $6}')"
SCRIPT_DIR="$(cd ${0%/*} && pwd -P)"
BACKUP_DIR="$USER_HOME/BACKUP"
MAVEN_DIR="$USER_HOME/.m2"
WIN_SETUP_DIR="/mnt/c/SRDEV/WSL/SETUP"
LINUX_SETUP_DIR="${USER_HOME}/SETUP"
ENV_PROP_FILE="${LINUX_SETUP_DIR}/swissre.environment"
cacert_file_path="/usr/local/share/ca-certificates"
INSTALL_JAVA=""
INSTALL_NODEJS=""
INSTALL_PYTHON=""

############################################################
# Show help message                                        #
############################################################
show_usage()
{
   # Display Help
   echo "This script can be invoked with a set of optional parameters"
   echo "The parameters secify optional packages to install"
   echo
   echo "Syntax: test-input-options.sh [-J|-N|-P|-h]"
   echo "options:"
   echo "J      Install Java SDK"
   echo "N      Install Node.js"
   echo "P      Install Python"
   echo "h      Print help and exit."
   echo
   exit 2
}

##################################################################
# Set variable                                                   #
##################################################################
set_variable()
{
  local varname=$1
  shift
  if [ -z "${!varname}" ]; then
    eval "$varname=\"$@\""
  else
    echo "Error: $varname already set"
    usage
  fi
}


# ##################################################################
# Utility function reads property by the specified key 
# from the environment property file
# ##################################################################
function read_prop {
    grep "${1}" ${ENV_PROP_FILE} | cut -d'=' -f2
}

# ##################################################################
# Utility function searches know downrectories on the 
# Windows file system for a GCM executable
# ##################################################################
find_gcm () {
    pgmgit=$(find /mnt/c/PROGRA~1/Git -iname ${1} -print -quit)
    if [[ "" == "$pgmgit" ]]; then
        srdevgit=$(find /mnt/c/SRDEV -iname ${1} -print -quit)
        echo $srdevgit
    else
        echo $pgmgit  
    fi   
}


##################################################################
# Process the input options. Add options as needed.              #
##################################################################
# Get the options
while getopts ":JHNPh:" option; do
   case $option in
      h) # display Help
        show-usage
        exit;;
      J) # Set JAVA
        set_variable INSTALL_JAVA true;;
      N) # Set Node.js
        set_variable INSTALL_NODEJS true;;
      P) # Set Python
        set_variable INSTALL_PYTHON true;;        
      ?) # Invalid option
        show_usage
        exit;;
   esac
done

##################################################################
# Main script. Runs several steps to configure environment       #
##################################################################
echo -e "\n---------------------------------------------------"
echo "1. Copying certs and env file from host to ~/SETUP"
echo -e "---------------------------------------------------"
echo "Disk usage: $(du -sh $USER_HOME)"
echo "Create ${BACKUP_DIR} if not found ..."
mkdir -p ${BACKUP_DIR}
echo "Create ${LINUX_SETUP_DIR} if not found ..."
mkdir -p ${LINUX_SETUP_DIR}

setup_files=("SwissReRootCA2.crt" "SwissReSystemCA22.crt"  "SwissReSystemCA25.crt"  "setup-devtools.sh"  "swissre.environment" "SwissReSystemCA21.crt"  "SwissReSystemCA24.crt"  "pki-cert-chain.crt" "setup-mdapt.sh" "settings.xml")

for sf in "${setup_files[@]}"
do
    win_path=${WIN_SETUP_DIR}/${sf}
    linux_path=${LINUX_SETUP_DIR}/${sf}
    echo "Win File: ${win_path}"
    echo "Linux File: ${linux_path}"

    if [ -f "$linux_path" ]; then
        echo "Old $linux_path found. Creating backup in $BACKUP_DIR ..."
        mv $linux_path $BACKUP_DIR/$sf-$(date ++%Y%m%d-%H%M%S)
        echo "Old $linux_path backed up!"    
    fi
    echo "Copying $win_path to $LINUX_SETUP_DIR ..."
    cp ${win_path} $LINUX_SETUP_DIR
done



echo -e "\n---------------------------------------------------"
echo "2. Get input parameters from user: "
echo -e "---------------------------------------------------"
read -p "Enter your Swiss Re user id: " srid
read -p "Enter your first name: "       fname
read -p "Enter your last name: "        lname
read -p "Enter your Swiss Re email address: " email

# Home directory of the logged-in user on host machine 
LOGGED_IN_USER_HOST_HOME="/mnt/c/Users/${srid^^}"

echo -e "\n---------------------------------------------------"
echo "3. Print out working environment:"
echo -e "---------------------------------------------------"
echo -e "User ID: ${srid}\nFirst name: ${fname}\nLast name: ${lname}\nEmail: ${email}"
echo "Logged-in user: $LOGGED_IN_USER"
echo "User home on Linux: $USER_HOME"
echo "User home on Windows host: $LOGGED_IN_USER_HOST_HOME"
echo "Script directory: $SCRIPT_DIR"
echo "Back up directory: $BACKUP_DIR"
echo "Maven directory: $MAVEN_DIR"
echo "Env property file: $ENV_PROP_FILE"


echo -e "\n---------------------------------------------------"
echo "4. Updating /etc/environment"
echo -e "---------------------------------------------------"
if [ ! -e /etc/environment ]; then
    echo "/etc/environment not found. Creating..."
    touch /etc/environment
    echo "/etc/environment created!"
else
    cp /etc/environment $BACKUP_DIR/environment_$(date +%Y.%m.%d-%H:%M:%S)
    echo "/etc/environment was found and backed up!"    
fi

echo "Greping /etc/environment!"    
cntprxenv=$(grep -o -E "http_proxy=" /etc/environment | wc -l)
echo "Grep /etc/environment was found $cntprxenv !"    
if [ $cntprxenv -lt 1 ]; then
    echo "No proxy statements found in /etc/environment..."
cat << EOF >> /etc/environment
http_proxy=$(read_prop 'http_proxy')
https_proxy=$(read_prop 'https_proxy')
ftp_proxy=$(read_prop 'ftp_proxy')
no_proxy=$(read_prop 'no_proxy')
EOF
    echo "Proxy statements addded to /etc/environments"
else
    echo "Nothing to do. Proxy already set!"
fi


echo -e "\n---------------------------------------------------"
echo "5. Updating /etc/apt/apt.conf"
echo -e "---------------------------------------------------"
echo "Updating apt.conf..."
if [ ! -e /etc/apt/apt.conf ]; then
    echo "apt.conf not found. Creating..."
    touch /etc/apt/apt.conf
    echo "/etc/apt/apt.conf created!"
    else
    cp /etc/apt/apt.conf  $BACKUP_DIR/apt.conf-$(date ++%Y%m%d-%H%M%S)
    echo "apt.conf found!"    
fi
cntprxapt=$(grep -o -E "Acquire::http::Proxy" /etc/apt/apt.conf | wc -l)
if [ $cntprxapt -lt 1 ]; then
    echo "No proxy statements found in /etc/apt/apt.conf..."
    cp /etc/apt/apt.conf $BACKUP_DIR/apt.conf_$(date +%Y.%m.%d-%H:%M:%S)
cat << EOF >> /etc/apt/apt.conf
Acquire::http::Proxy $(read_prop 'http_proxy');
Acquire::https::Proxy $(read_prop 'https_proxy');
EOF
    echo "Proxy statements addded to /etc/apt/apt.conf"
else
    echo "Nothing to do. Proxy already set!"
fi

echo -e "\n---------------------------------------------------"
echo "6. Updating ~/.curlrc"
echo -e "---------------------------------------------------"
if [ ! -e $USER_HOME/.curlrc ]; then
    echo ".curlrc not found. Creating..."
    touch "$USER_HOME/.curlrc"
    echo "$USER_HOME/.curlrc created!"
    else
    cp $USER_HOME/.curlrc  $BACKUP_DIR/.curlrc-$(date +%Y.%m.%d-%H:%M:%S)
    echo ".curlrc and backed up!"    
fi

cntprxcurl=$(grep -o -E "cacert|pki-cert-chain.crt" $USER_HOME/.curlrc | wc -l)
if [ $cntprxcurl -lt 1 ]; then
    echo "No certificate path statements found in $USER_HOME/.curlrc..."

cat << EOF >> $USER_HOME/.curlrc
proxy=http://prx.global.swissre.com:8080
noproxy=127.0.0.1,localhost,swissreapps.com,gwpnet.com,swissre.com,192.168.1.0/24
cacert=${cacert_file_path}/pki-cert-chain.crt
cert-type=PEM
EOF
    echo "DONE: certificate statements addded to $USER_HOME/.curlrc"
else
    echo "Nothing to do. Certificate path  already set!"
fi


echo -e "\n---------------------------------------------------"
echo "7. Updating ~/.wgetrc"
echo -e "---------------------------------------------------"
if [ ! -e $USER_HOME/.wgetrc ]; then
    echo ".wgetrc not found. Creating..."
    touch "$USER_HOME/.wgetrc"
    echo "$USER_HOME/.wgetrc created!"
    else
    cp $USER_HOME/.wgetrc  $BACKUP_DIR/.wgetrc-$(date +%Y.%m.%d-%H:%M:%S)
    echo ".wgetrc backed up!"    
fi

echo "Grepping ~/.wgetrc for existing proxy or certifiacte entries... "    
cntprxwg=$(grep -o -E "http_proxy|ca_certificate" $USER_HOME/.wgetrc | wc -l)
echo "No. of entries found: $cntprxwg"

if [ $cntprxwg -lt 1 ]; then
    echo "No Certitificate path statements found in $USER_HOME/.wgetrc ..."

cat << EOF >> $USER_HOME/.wgetrc
http_proxy=prx.global.swissre.com:8080
https_proxy=prx.global.swissre.com:8080
no_proxy=127.0.0.1,localhost,swissreapps.com,gwpnet.com,swissre.com,192.168.1.0/24
ca_certificate=${cacert_file_path}/pki-cert-chain.crt
EOF
    echo "DONE: certitificate statements addded to $USER_HOME/.wgetrc"
else
    echo "Nothing to do. Proxy and certitificate path already set!"
fi


echo -e "\n---------------------------------------------------"
echo "8. Installing PKI certificates ..."
echo -e "---------------------------------------------------"
echo "Copying PKI certificates to ${cacert_file_path} ..."

cacert_files=("SwissReRootCA2.crt" "SwissReSystemCA22.crt"  "SwissReSystemCA25.crt" "SwissReSystemCA21.crt"  "SwissReSystemCA24.crt"  "pki-cert-chain.crt")


for ctf in "${cacert_files[@]}"
do
    cert_file=${LINUX_SETUP_DIR}/${ctf}
    echo "Copying $cert_file to $cacert_file_path ..."
    cp --force $cert_file "/usr/local/share/ca-certificates/"
done

echo "Reconfiguring ca-certificates packages ...."
dpkg-reconfigure ca-certificates

echo "Updating the directory /etc/ssl/certs  ...."
update-ca-certificates


echo -e "\n---------------------------------------------------"
echo "9. Register GCM with /usr/local/bin/git-credential-manager"
echo -e "---------------------------------------------------"
if [ ! -e /usr/local/bin/git-credential-manager ]; then
    gcm_windows=$(find_gcm 'git-credential-manager.exe')

    echo "Search for Windows Git Credentials Manager retunrs ${gcm_windows}"

    if [ "" == "$gcm_windows" ]; then
        echo "Could not find Windows Git or the Git Credentials Manager. 
              Please install Git from SNOW or Chocolatey and try again"
        exit
    else
        echo "creating git_credential_manager in /usr/local/bin, using ${gcm_windows}"
        tee /usr/local/bin/git-credential-manager 1> /dev/null << EOF
#!/bin/bash
set -eu

GIT_EXEC_PATH="\$(git --exec-path)"
export GIT_EXEC_PATH
export WSLENV="\${WSLENV}:GIT_EXEC_PATH/wp"
exec $gcm_windows "\${@}"
EOF
        chmod +x /usr/local/bin/git-credential-manager
    fi
else
    echo "Nothing to do. LinuxGit Credentials Manager not found under /usr/local/bin/git-credential-manager"  
fi


echo -e "\n---------------------------------------------------"
echo "10. Updating ~/.gitconfig"
echo -e "---------------------------------------------------"
if [ ! -e $USER_HOME/.gitconfig ]; then
    echo ".gitconfig not found. Creating..."
    touch "$USER_HOME/.gitconfig"
    echo "$USER_HOME/.gitconfig created!"
else
    cp $USER_HOME/.gitconfig  $BACKUP_DIR/.gitconfig-$(date +%Y.%m.%d-%H:%M:%S)
    echo ".gitconfig backed up!"    
fi

echo "Grepping ~/.gitconfig for existing proxy entries... "    
cntprxgit=$(grep -o -E "https://" $USER_HOME/.gitconfig | wc -l)
echo "Number of entries found: $cntprxgit"

if [ -e $LOGGED_IN_USER_HOST_HOME/.gitconfig ]; then
    echo "Found a local .gitconfig in $LOGGED_IN_USER_HOST_HOME"
    echo "will copy $LOGGED_IN_USER_HOST_HOME/.gitconfig to $USER_HOME ...."
    cp -f $LOGGED_IN_USER_HOST_HOME/.gitconfig $USER_HOME
    echo "Host $LOGGED_IN_USER_HOST_HOME/.gitconfig copied to $USER_HOME!!"    
else
    echo "No local .gitconfig found on host in $LOGGED_IN_USER_HOST_HOME', will create one if no local copies found"
    if [ $cntprxgit -lt 1 ]; then
        echo "No proxy statements found in $USER_HOME/.gitconfig ..."
        echo "$ whoami says: " && whoami 
        echo "$LOGGED_IN_USER is expected"
sudo -u $LOGGED_IN_USER bash <<EOF
git config --global user.name "${fname} ${lname}"
git config --global user.email ${email}
git config --global http.proxy $(read_prop 'http_proxy')
git config --global https.proxy $(read_prop 'http_proxy')
git config --global http.sslCAInfo /usr/local/share/ca-certificates/pki-cert-chain.crt
git config --global credential.helper "/mnt/c/Program\ Files/Git/mingw64/bin/git-credential-manager.exe"
git config --global credential.https://dev.azure.com.useHttpPath true
git config --global core.autocrlf input
git config --global pull.rebase true
EOF
        echo "DONE: Proxy statements addded to $USER_HOME/.gitconfig"    
    else
        echo "Nothing to do. Proxy already set!"
    fi
fi


echo -e "\n---------------------------------------------------"
echo "11. Updating Maven config file ~/.m2/settings.xml"
echo -e "---------------------------------------------------"
if [ ! -e $MAVEN_DIR ]; then
    echo "$MAVEN_DIR not found. Creating..."
    mkdir $MAVEN_DIR
fi

if [ ! -e $MAVEN_DIR/settings.xml ]; then
    echo "$MAVEN_DIR/settings.xml not found. Dowloading default ..."
    wget -P ${MAVEN_DIR} https://artifact.swissre.com/sr-devtools-generic-local/maven/settings.xml --no-proxy
    echo "Default settings.xml downloaded to $MAVEN_DIR..."
else
    echo "$MAVEN_DIR/settings.xml found. Nothing to do." 
fi

echo -e "\n---------------------------------------------------"
echo "12. Update apt package list and upgrade"
echo -e "---------------------------------------------------"
apt update -y
apt upgrade -y

echo -e "\n---------------------------------------------------"
echo "13. Install OpenJDK 21"
echo -e "---------------------------------------------------"
echo "Resolving Java home dictory"
#java_install_dir=$(readlink -f `which java` | sed "s:/bin/java::")
# java_install_dir=$(which java)
# echo -e "Java home: $java_install_dir"
# if [ -z $java_install_dir ]; then
if [ -n `which java` ]; then
    echo -e "Java not found. Will install openjdk-21-jdk..."
    apt install openjdk-21-jdk -y
    cntprxenv=$(grep -o "JAVA_HOME=" /etc/environment | wc -l)
    if [ $cntprxenv -lt 1 ]; then
        echo -e "No JAVA_HOME entries found"
        cp /etc/environment $BACKUP_DIR/environment_$(date +%Y.%m.%d-%H:%M:%S)
cat << EOF >> /etc/environment
JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
EOF
        echo "JAVA_HOME statement addded to /etc/environments"
    else
        echo "Nothing to do. JAVA_HOME already set!"
    fi
else
    echo -e "A Java JDK is already installed..."
fi

echo -e "\n---------------------------------------------------"
echo "14. Install WSL Utilities package wslu"
echo -e "---------------------------------------------------"
echo "Installing wslu..."
apt install wslu -y


echo -e "\n---------------------------------------------------"
echo "15. Update .bashrc to source environment varaiables from swissre.environment"
echo -e "---------------------------------------------------"
cntdisplay=$(grep -o "export DISPLAY=:0" $USER_HOME/.bashrc | wc -l)
if [ $cntdisplay -lt 1 ]; then
    echo "no export DISPLAY statement in $USER_HOME/.bashrc..."
    cp $USER_HOME/.bashrc $BACKUP_DIR/.bashrc_$(date +%Y.%m.%d-%H:%M:%S)
cat << EOF >> $USER_HOME/.bashrc

#
# Set display to the first (normally X Server)
export DISPLAY=:0
EOF
    echo "export DISPLAY statements addded to $USER_HOME/.bashrc"
else
    echo "Nothing to do. DISPLAY already set!"
fi

cntenvironment=$(grep -o "swissre.environment" $USER_HOME/.bashrc | wc -l)
if [ $cntenvironment -lt 1 ]; then
    echo "no swissre.environment statement in $USER_HOME/.bashrc..."
    cp $USER_HOME/.bashrc $BACKUP_DIR/.bashrc_$(date +%Y.%m.%d-%H:%M:%S)
cat << EOF >> $USER_HOME/.bashrc

#
# Read environment settings from property file
set -a
source $USER_HOME/swissre.environment
set +a
EOF
    echo "swissre.environment statements added to $USER_HOME/.bashrc"
else
    echo "Nothing to do. swissre environment already set!"
fi

cntbrowser=$(grep -o "export BROWSER=/usr/bin/wslview" $USER_HOME/.bashrc | wc -l)
if [ $cntbrowser -lt 1 ]; then
    echo "no export BROWSER statement in $USER_HOME/.bashrc..."
    cp $USER_HOME/.bashrc $BACKUP_DIR/.bashrc_$(date +%Y.%m.%d-%H:%M:%S)
cat << EOF >> $USER_HOME/.bashrc

#
# Set browser path
export BROWSER=/usr/bin/wslview
EOF
    echo "export BROWSER  statements addded to $USER_HOME/.bashrc"
else
    echo "Nothing to do. export BROWSER already set!"
fi


############################################################
############################################################
# Install SDKs and platforms                               #
############################################################
############################################################

if [[ -n $INSTALL_JAVA ]]; then
  echo "Java is installed by default"
fi

if [[ -n $INSTALL_NODEJS ]]; then
  echo "Installing Node.js..."
  #apt install nodejs
  
  echo "Installing npm..."
  #apt install npm
fi

############################################################
# Install Python
############################################################
# See https://phoenixnap.com/kb/how-to-install-python-3-ubuntu
if [[ -n $INSTALL_PYTHON ]]; then
    python_version=3.13.3
    echo "Installing Python ${python_version}"
    apt update -y
    apt upgrade

    apt install -y make build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev llvm libncurses5-dev libncursesw5-dev xz-utils tk-dev

    mkdir python_installation && cd python_installation

    wget https://www.python.org/ftp/python/${python_version}/Python-${python_version}.tgz

    tar xzvf Python-${python_version}.tgz
    rm -f Python-${python_version}.tgz

    cd Python-${python_version}
    ./configure --enable-optimizations --with-ensurepip=install
    make -j 4
    make altinstall

    cd ../..
    rm -rf python_installation

    apt --purge remove build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev libffi-dev -y
    
    apt autoremove -y
    apt clean

    echo '$alias pip3="python3 -m pip"' >> ~/.bashrc  
fi